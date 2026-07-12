## Context

Ghostty 内建链接检测（`ThirdParty/ghostty/src/config/url.zig`）已匹配三类文本：带 scheme 的 URL、rooted/dot-relative 路径（`/`、`./`、`../`、`~/`）、裸相对路径（`src/foo.zig` 式，须含 `/`）。`path_chars` 含 `:` 且只禁止以冒号结尾，所以 `supacode/Foo.swift:123` 会整串匹配。点击流（`Surface.zig:4334 processLinks`）：

- `.open`（正则命中）：相对路径先经 `resolvePathForOpening`（OSC 7 pwd + `accessAbsolute` 存在性校验）。**带 `:line` 后缀的路径校验必失败**（磁盘上没有叫 `Foo.swift:123` 的文件）→ 回退为原始字符串发给 apprt。
- `._open_osc8`（OSC 8 超链接）：URI 原样发给 apprt。

两条路都到 `GHOSTTY_ACTION_OPEN_URL` → `GhosttySurfaceBridge.swift:457-466`，目前无条件 `NSWorkspace.shared.open`。相对字符串被 `URL(filePath:)` 拼在 app 进程 cwd 上，点击 `path:line` 今天就是坏的。

Ghostty 的 `link` 自定义正则配置未实现（`Config.zig:8545 RepeatableLink.parseCLI` → `error.NotImplemented`），config 路线不通；仓库虽有 patch ghostty 先例，但 Swift 侧拦截零 Zig 改动即可覆盖需求。

已有可复用件：

- diff viewer：`RepositoriesFeature+GitHistory.swift` 的 `GitHistoryAction.fileTapped(source:path:)`（`:183-214`）接**相对 worktree 根的路径**，`PresentedFileDiff.Source` 支持 `.uncommitted`。约束：`state.gitHistory` 仅在 History pane 可见时存在；其初始化靠 gitHistoryReducer **default-arm 对账**（`:258-276`），且 gitHistoryReducer 排在主 reducer 之后。
- 事件管线：bridge 回调（`view.bridge.onX`，`WorktreeTerminalState` 接线，守 `isLiveSurface`）→ `WorktreeTerminalManager.emit(TerminalClient.Event)` → `AppFeature.terminalEvent` → 转发 `.repositories(...)`。
- 上下文：`WorktreeTerminalState` 持有 `worktree`（根 = `worktree.workingDirectory`）；surface 实时 pwd 在 `GhosttySurfaceState.pwd`（OSC 7）。

## Goals / Non-Goals

**Goals:**
- Cmd+click 终端里的 `path`、`path:line`、`path:line:col` 引用（Ghostty 内建正则可匹配者）→ 选中 worktree 的 History pane 打开 + diff sheet 展示该文件 uncommitted diff。
- OSC 8 `file://` 超链接（如 `ls --hyperlink`、agent 输出）指向 worktree 内文件时同样直达 diff sheet。
- 带行号时 diff sheet 自动滚动到目标行。
- 非命中（http 等 scheme、worktree 外、文件不存在、远程 worktree）行为不变：`NSWorkspace.open`。

**Non-Goals:**
- 匹配不含 `/` 的单段文件名（`Package.swift:3`）——上游正则限制，不 patch Zig。
- commit 来源的 diff（点击只可能指当前工作区文件 → `.uncommitted`）。
- `supacode://` deeplink 新增 diff 路由（已注册的 scheme 经 `NSWorkspace.open` 本就能回到 app；扩 `Deeplink` enum 留作后续）。
- 远程 SSH worktree（本地磁盘无从校验路径存在性）。
- diff sheet 内目标行高亮/列定位（只滚动）。

## Decisions

### D1: 拦截点 = bridge 的 open-url 分支加一个可否决回调，不动 Zig

`GhosttySurfaceBridge` 新增 `var onOpenURL: ((String) -> Bool)?`（参数为 Ghostty 送来的**原始字符串**——`ghosttyOpenURLRequest` 的 fileURL 转换会破坏相对路径语义，拦截判定必须在转换前）。`GHOSTTY_ACTION_OPEN_URL` 分支先问回调，返回 `true` 即拦下，否则走现有 `NSWorkspace` 路径。与现有十余个 `onX` 回调同构。

备选（弃）：patch Zig 实现 `link` 配置正则——维护 patch 成本高，且行号定位、worktree 归属判断本来就得在 Swift 侧做。

### D2: 解析器是纯函数，磁盘探测注入

新类型 `TerminalFileReference`（caseless enum 静态方法或 struct + static resolve，放 `Features/Terminal/Models/`）：

```swift
struct TerminalFileReference: Equatable {
  let relativePath: String  // 相对 worktree 根，git 语义
  let line: Int?

  static func resolve(
    clicked: String,          // 原始点击文本或 OSC 8 URI
    pwd: String?,             // surface 实时 pwd（OSC 7），nil 则用 worktree 根
    worktreeRoot: URL,
    fileExists: (String) -> Bool  // 注入，测试不碰磁盘
  ) -> TerminalFileReference?
}
```

规则：
1. `file://` URI → 取 path，无行号。带其他 scheme（http/mailto/…）→ nil。
2. 纯文本 → 候选序列：原串、剥 `:line:col`、剥 `:line`（**原串优先**：真有叫 `foo.txt:12` 的文件时精确命中赢）。
3. 每个候选：相对路径以 pwd（缺省 worktree 根）为基准 resolve → standardize → `fileExists` → 必须位于 `worktreeRoot` 之下（前缀含分隔符判断）→ 产出相对路径。
4. 全不中 → nil（调用方回退系统打开）。

### D3: 接线沿用 bridge 回调 → TerminalClient.Event → AppFeature 转发

- `WorktreeTerminalState` 在 surface 接线处设 `onOpenURL`：守 `isLiveSurface`，仅本地 worktree（远程直接 `false`），用 `view.bridge.state.pwd` + `worktree.workingDirectory` 调 `resolve`；命中 → `onFileReferenceClicked?(relativePath, line)` 并返回 `true`。
- `WorktreeTerminalManager` 接线为 `emit(.fileReferenceClicked(worktreeID:path:line:))`（`TerminalClient.Event` 新 case）。
- `AppFeature.terminalEvent(.fileReferenceClicked)` → `.send(.repositories(.openTerminalFileReference(worktreeID:path:line:)))`。

### D4: 编排 case 放 RepositoriesFeature 主 switch，靠既有 default-arm 对账初始化 gitHistory

`openTerminalFileReference` 在**主 reducer** 处理（主 reducer 排在 gitHistoryReducer 之前）：

1. guard `worktreeID == state.selectedWorktreeID`（点击必然来自选中 worktree 的可见终端，不成立即丢弃——不重放 `selectWorktree` 的全套副作用）。
2. `inspectorPresented = true`、`inspectorPane = .history`。
3. 返回 `.send(.gitHistory(.fileTapped(source: .uncommitted, path:, line:)))`。

关键时序：本 action 稍后流经 gitHistoryReducer 的 **default 分支**，对账看到 pane 可见 + `gitHistory.worktreeID` 不匹配 → 初始化 `gitHistory` 并启动加载。随后 `fileTapped` 到达时 `state.gitHistory != nil`，guard 通过。零逻辑重复。

备选（弃）：在 gitHistoryReducer 显式 case 里处理——显式分支不跑对账，得手工调 `startGitHistoryLoad` + 复制 `fileTapped` 逻辑。

### D5: 行号定位——`fileTapped` 扩 `line: Int?`，sheet 用 ScrollViewReader

- `GitHistoryAction.fileTapped(source:path:line:)`（enum case 无默认值，两个现有视图调用点补 `line: nil`）；`PresentedFileDiff` 增 `targetLine: Int?`。
- `WorktreeFileDiffSheetView`：diff 装载后（`onChange(of: diff)`）用 `ScrollViewReader.scrollTo` 定位到首个 `newNumber >= targetLine` 的行（行 id 复用现有渲染行标识），找不到（行号超界/文件被删）不滚动。行号超过 `maxRenderedLines = 4000` 截断上限时同样不滚动。

### D6: 媒体/二进制文件分流系统打开（追加）

图片/PDF/音视频/压缩包/office 等扩展名（大小写不敏感）没有可读文本 diff，`TerminalFileReference.prefersSystemOpen` 判定后在 `handleOpenURL` 里直接 `NSWorkspace.open(worktree 根 + relativePath)`，不进 diff viewer。用解析出的绝对路径（而非放行回退）是因为原回退路径对相对字符串拼的是 app 进程 cwd，本来就打不开。

### D7: 测试

- `TerminalFileReference.resolve` 纯函数单测：绝对/相对、pwd 有无、`:line`、`:line:col`、原串精确命中优先、worktree 外、不存在、`file://`、http scheme、前缀伪匹配（`/repo-other` 不算 `/repo` 内）。
- `RepositoriesFeature` TestStore：`openTerminalFileReference` → inspector 状态翻转、gitHistory 对账初始化、`fileTapped` 续发、`presentedDiff.targetLine` 落位；非选中 worktree 事件丢弃。沿用现有 GitHistory 测试的 client stub 模式。
- bridge 回调本身薄到无逻辑（问回调、fallback），不为 `NSWorkspace` 建测试缝。

## Risks / Trade-offs

- [文件存在但无未提交改动 / untracked → diff 为空] → sheet 已定义空 diff 状态，且自带 Open in Editor 按钮兜底；可接受，不做"先探测再分流"。
- [`accessAbsolute` 让**不带行号且存在**的相对路径在 Zig 侧就解析成绝对路径] → 解析器对绝对路径同样处理（worktree 归属判断不受影响），行为一致。
- [OSC 7 pwd 缺失（shell 未集成）时相对路径基准退化为 worktree 根] → 多数 agent 输出的引用本就相对仓库根，退化正确；深层 cd 后的相对引用可能 miss → 回退系统打开，无害。
- [双击/拖选与 Cmd+click 冲突、hover 样式] → 完全复用 Ghostty 既有链接交互，无新增手势。
- [`fileTapped` 签名变更波及现有测试] → 调用点仅 `WorktreeGitHistoryInspectorView` 两处 + 若干测试，编译器兜底。

## Open Questions

无阻塞项。
