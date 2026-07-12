# Terminal File Link → Diff Viewer

## Why

Agent（Claude Code 等）在终端里大量输出 `path/to/file.swift:123` 式文件引用。Ghostty 内建链接检测已能识别这些裸路径并使其可点击（Cmd+click），但点击后 Supacode 只是把原始字符串拼成 fileURL 丢给 `NSWorkspace.open`——带 `:line` 后缀的相对路径根本打不开，等于坏的。用户想看的其实是"这个文件改了什么"：点击应直通已有的 History diff viewer。

## What Changes

- 拦截 Ghostty 的 `GHOSTTY_ACTION_OPEN_URL`：当点击目标是当前 worktree 内的文件引用（裸 `path`、`path:line`、`path:line:col`，或 OSC 8 的 `file://` 超链接）时，不再交给系统打开，而是在 History diff viewer 中打开该文件的 uncommitted diff。
- 新增纯函数文件引用解析器：剥离 `:line(:col)` 后缀、基于 surface 实时 pwd（OSC 7）解析相对路径、校验文件存在且位于 worktree 根之下，产出相对 worktree 根的 git 路径 + 可选行号。
- diff sheet 支持目标行定位：携带行号打开时自动滚动到对应行。
- 非文件引用（http 等 scheme、worktree 外路径、不存在的文件、远程 SSH worktree）保持现状，回退 `NSWorkspace.open`。

## Capabilities

### New Capabilities

- `terminal-file-links`: 终端内文件引用点击的检测、解析与路由——从 Ghostty open-url action 拦截，到解析为 worktree 相对路径 + 行号，到在 History diff viewer 中打开（含 diff sheet 行号定位、非命中场景回退系统打开）。

### Modified Capabilities

（无——`openspec/specs/` 尚无已归档 spec；diff sheet 的行号定位作为 `terminal-file-links` 的一部分声明。）

## Impact

- **受影响代码**：
  - `supacode/Infrastructure/Ghostty/GhosttySurfaceBridge.swift`（open-url 拦截回调）
  - `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`（回调接线 + pwd/worktree 上下文）
  - `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift` + `supacode/Clients/Terminal/TerminalClient.swift`（新 `Event` case）
  - `supacode/Features/Repositories/Reducer/RepositoriesFeature+GitHistory.swift`（打开 History pane + `fileTapped` 编排、`PresentedFileDiff` 携带目标行）
  - `supacode/Features/Repositories/Views/WorktreeFileDiffSheetView.swift`（滚动到目标行）
  - 新解析器类型 + 单元测试
- **不改 Ghostty Zig 源码 / 不加 patch**：Ghostty 的 `link` 自定义正则配置未实现（`Config.zig` `RepeatableLink.parseCLI` 返回 `NotImplemented`），但内建正则已匹配裸相对/绝对路径含 `:line` 后缀，Swift 侧拦截即可。
- **无新依赖、无数据迁移、无接口破坏**。
