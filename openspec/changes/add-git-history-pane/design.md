## Context

Supacode 的 detail 区已有一套 SwiftUI `.inspector` 系统：`WorktreeInspectorPane`（`RepositoriesFeature.swift:80`，目前 `git` / `notifications` 两个 case）+ `inspectorPresented` / `inspectorPane` 状态（`RepositoriesFeature.swift:139-140`）+ `WorktreeStatusInspectorContainer` 按 pane 分发视图 + 工具栏 Toggle（`WorktreeStatusToolbarItems.swift`）+ 菜单命令与快捷键（`SidebarCommands.swift`、`AppShortcuts`）。

Git 侧：`GitClient`（`Clients/Git/GitClient.swift`）经 `ShellClient` 跑 git 命令，已有 `lineChanges`（diff shortstat）、`symbolicHeadBranch` 等只读查询，但没有任何 `git log` 封装。`WorktreeInfoWatcherClient` 只监听当前选中 worktree，发 `branchChanged` / `filesChanged` 事件，现由 `SidebarItemFeature` 消费刷新分支名和 diff 行数。

约束：
- sidebar 行不可扇出失效（CLAUDE.md）；历史状态不能塞进 `SidebarItemFeature.State`，否则每次 log 刷新都会波及 sidebar。
- Inspector 列宽 min 280 / ideal 320 / max 480，视图要在窄列下可读。
- Reducer 逻辑变更必须配测试；不用 `Task.sleep`，用 `TestClock`。

## Goals / Non-Goals

**Goals:**
- 第三个 inspector pane「History」：当前选中 worktree 的线性提交历史（first-parent），带图点连线、分支/远程徽章、未提交更改节点、传出更改分组。
- 点击提交行展开详情（懒加载改动文件统计）。
- 历史随 worktree 切换与 watcher 事件自动刷新；pane 关闭时不产生任何 git 调用。
- 复制 hash / 消息的右键菜单（顺手、零成本）。

**Non-Goals:**
- 多分支拓扑泳道图（`--all` 多列图线）。
- 任何写操作（checkout、reset、cherry-pick、push/pull）。
- 每个 worktree 的历史缓存（只保留当前选中项，切换即重查）。
- 远程 worktree（`WorktreeLocation.remote`）第一版按"不可用"空态处理（见 Open Questions）。

## Decisions

### D1: 状态放 `RepositoriesFeature.State`，新建扩展文件，不做独立子 Reducer

`RepositoriesFeature.State` 新增单个 `gitHistory: GitHistoryState?`（仅代表当前选中 worktree，类比 `selectedWorktreeSlice` 的"只缓存选中项"模式），reducer 逻辑放新文件 `RepositoriesFeature+GitHistory.swift`，沿用现有 `+Sidebar` / `+Remote` 扩展拆分惯例。

- 为什么不放 `SidebarItemFeature`：历史刷新是高频较重的 payload，放进 sidebar 行状态违反"per-leaf 失效"约束。
- 为什么不做独立 `@Reducer` 子 feature：pane 的 presented/pane 状态机已在 Repositories 层，历史加载依赖 `selectedWorktreeID` 和 watcher 事件转发，拆子 feature 徒增 action 转发样板。

`GitHistoryState`（Equatable、Sendable）：`commits: [GitCommitSummary]`、`upstreamRef: String?`、`aheadCount: Int`、`isLoading`、`loadError: String?`、`expandedCommitHash: String?`、`expandedDetail: GitCommitDetail?`。

### D2: 单次 `git log` 拿全列表，`%D` 解码 decorations，upstream 分界定位"传出的更改"

新增 `GitClient.commitHistory(at:limit:)`：

```
git log --first-parent -n 200 --format=%H%x1f%h%x1f%an%x1f%aI%x1f%D%x1f%s%x1e
```

- `%x1f`（unit separator）分字段、`%x1e`（record separator）分记录，避免消息里的换行/制表符破坏解析。解析器是 `nonisolated static` 纯函数（`GitClient.parseCommitLog(_:)`），可直接单测——沿用 `parseWorktreePorcelain` 的模式。
- `%D` 直接给出每个 commit 上的 ref decorations（`HEAD -> main, origin/main`），拆成徽章，无需第二次 branch 查询。
- 传出的更改：同一 effect 里再跑 `git rev-parse --abbrev-ref @{upstream}`（失败即无 upstream）与 `git rev-list --count @{upstream}..HEAD`。列表前 `aheadCount` 个 commit 归入「传出的更改」分组头——对 first-parent 线性列表成立。
  - 备选（弃）：解析 `%D` 里第一个 `origin/*` 出现位置做分界——upstream 不一定叫 `origin/<branch>`，且 upstream 可能不在前 200 条内。`rev-list --count` 语义精确且便宜。
- limit 固定 200，不做分页。200 条足够"看看最近改动"的场景；`--first-parent` + `-n` 在大仓库下也是毫秒级。列表底部显示"仅显示最近 200 条"提示。

### D3: 详情懒加载：点击展开时才跑 `git show`

`GitClient.commitDetail(at:hash:)` 封装：

```
git show <hash> --numstat --format=%H%x1f%an%x1f%ae%x1f%aI%x1f%B%x1e --first-parent
```

body（`%B`）+ numstat 行（每文件 added/removed/path）。只缓存当前展开的一条（`expandedDetail`），再点别的行就丢弃重查——避免无界缓存。展开中显示行内 `ProgressView`。

### D4: 刷新时机——组合 `gitHistoryReducer` 的 default-arm 对账（实现后修订）

实现沿用仓库既有的"组合子 reducer + 主 switch catch-all"模式（同 `worktreeNotificationReducer`）：`gitHistoryReducer` 排在 body 中所有会改 inspector / selection 状态的 reducer 之后，其 `default` 分支在每个 action 后做一次廉价对账（两个字段比较）：

1. pane 不可见或无选中 → `gitHistory = nil` + `.cancel` 在途查询（零 git 调用）；
2. 可见且 `gitHistory?.worktreeID != selectedWorktreeID` → 启动加载。

这一条覆盖了 toggle / setPresented / 一切 selection 变化路径，无需逐个枚举 action。显式分支只处理两类：

- `.worktreeInfoEvent(.branchChanged/.filesChanged)`（watcher 直达 RepositoriesFeature，非 sidebar 子 action）且事件属于选中 worktree 且可见 → 原地刷新（保留旧 snapshot，置 `isLoading`）；
- `.sidebarItems(.element(_, .diffStatsChanged))` → 同步未提交 +/- 到 `GitHistoryState.uncommittedAdded/Removed`。

effect 用固定 cancel ID + `cancelInFlight`，切 worktree 自动取消串台查询。

未提交更改节点（实现修正）：`SelectedWorktreeSlice` 刻意不含 diff 行数（`diffStatsChanged` 的 cacheInvalidations 为 `[]`），不能走该投影；改为在加载时从 `sidebarItems[id:]` 行状态种子化 + 拦截 `diffStatsChanged` 增量同步，数据仍复用现有 watcher 管线，无额外 git 调用。

### D5: 视图——`Form.grouped` + 行内自绘图线，跟随现有 pane 风格

新文件 `Features/Repositories/Views/WorktreeGitHistoryInspectorView.swift`：

- 外层结构复刻现有 pane：headline 标题栏（"History" + 刷新按钮）+ `Divider` + `Form.formStyle(.grouped)` + `.scrollContentBackground(.hidden)`（透出终端 chrome 背景）。
- 图线列：每行 leading 一个固定宽（约 16pt）的图形单元——圆点 + 上下延伸的竖线，用 `Circle` + `Rectangle`（系统色 `.secondary` / accent），首行（未提交节点）用空心圆。不需要 Canvas，线性单泳道纯 shape 即可。
- 徽章：`%D` 解析出的 ref 名渲染成小胶囊（`.capsule` 背景 + `.caption` 字体），本地分支与远程分支用系统色区分（如 `.tint` vs `.secondary`）；HEAD 指向的分支加粗。
- 分组：`Section("传出的更改")`（英文 UI 下为 "Outgoing"，遵循现有英文界面）包住前 `aheadCount` 条；其余在无标题 Section。
- 展开详情：行点击切换 `expandedCommitHash`，展开区内嵌完整消息（`textSelection(.enabled)`）、作者/时间/hash、文件列表（+/- 绿红，`monospaced`）。
- 右键菜单：Copy Hash / Copy Message。
- 空态/错误态：folder 仓库复用现有 `ContentUnavailableView("Not a Git Repository")` 措辞；加载失败显示错误 `ContentUnavailableView` + Retry。
- 相对时间用 `TimelineView(.everyMinute)`，同通知 pane。

### D6: 工具栏按钮、菜单、快捷键完全照抄现有 pane 的三件套

- `WorktreeStatusToolbarItems.swift` 加 `WorktreeGitHistoryToolbarButton`（`clock.arrow.circlepath` 或 `list.bullet.rectangle` 系统符号），tint/foreground 传参与现有两个按钮一致。
- `WorktreeDetailView.TrailingStatusToolbarContent` 插入按钮，位置在 git 按钮旁。
- `AppShortcuts` 加 `toggleHistoryInspector`；`SidebarCommands.swift` 照 78-118 行模式加菜单项，走既有 `toggleInspectorPaneAction` FocusedValue。
- `WorktreeInspectorPane` 加 `case history`；注意该枚举若参与持久化/编码需检查兼容（当前是内存态，无持久化）。

## Risks / Trade-offs

- [大仓库 `git log` 慢或卡] → `--first-parent -n 200` 上界固定；查询在 effect 里异步跑，UI 显示 loading；cancellable 防切换串台。
- [`%D` decorations 含 tag、多 ref，解析歧义] → 解析器纯函数 + 单测覆盖：无 decoration、`HEAD -> branch`、`tag: v1`、多 ref 逗号分隔、detached HEAD。
- [无 upstream（新分支未 push）/ detached HEAD] → `rev-parse @{upstream}` 失败即 `aheadCount = 0`，不显示传出分组，列表照常。
- [watcher 只盯选中 worktree，后台 commit（如 agent 在别的 worktree 提交）不触发刷新] → 接受：pane 只服务选中 worktree，切换选中时必然重查；另提供手动刷新按钮兜底。
- [拦截子 action 造成耦合] → 只读拦截（TCA 父 reducer 观察子 action 是官方模式），且收敛在 `+GitHistory` 扩展一处。
- [中文/emoji 提交消息破坏解析] → `%x1f/%x1e` 控制符不会出现在合法 UTF-8 文本中；单测含 emoji 与多行消息用例。

## Open Questions（已收口）

- 远程 worktree：**已支持**。`GitClientDependency.ssh(host:)` 把所有 git shell-out 跑在远端 host 上，`historyGitClient(for:)` 按 `worktree.host` 选 transport，history 查询免费获得远程能力，无需"不可用"空态。
- 快捷键定为 ⌘⌥L（git log 之意；⌘⌥H 与系统"隐藏其他"冲突，⌘⌥G/N 已被占用）。
- 工具栏第三个按钮是否拥挤：留待 `make run-app` 目验（任务 5.2）。
