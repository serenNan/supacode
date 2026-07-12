## Why

Supacode 目前只在 sidebar 展示每个 worktree 的分支名和未提交 diff 行数（+/-），用户无法在应用内查看提交历史——不知道本地领先远程多少个提交（传出的更改）、每个提交改了什么，必须切到终端跑 `git log` 或打开 VS Code。作为一个以 Git worktree 为核心的工具，缺少提交历史视图是明显的能力空白。

## What Changes

- 右侧 Inspector 新增第三个 pane「History」，与现有 Git/PR、Notifications 面板并列，展示当前选中 worktree 的提交历史。
- 提交列表为线性历史（当前分支 first-parent），包含：
  - 图点连线（类似 VS Code Git Graph 的单泳道样式）
  - 提交消息、作者、相对时间
  - 分支/远程标记徽章（如 `main`、`origin/main`、HEAD 指示）
  - 顶部「未提交的更改」节点（工作区有改动时显示）
  - 「传出的更改」分组标记（本地领先 upstream 的提交）
- 点击提交行展开详情：完整消息、作者、绝对时间、hash、改动文件列表及 +/- 统计。
- 工具栏新增 History 切换按钮（仿现有 `WorktreeGitStatusButton`），菜单命令与快捷键跟随现有 inspector pane 模式。
- `GitClient` 新增提交历史查询（`git log` 封装）与提交详情查询（改动文件统计）。
- 历史随 `WorktreeInfoWatcherClient` 的 `branchChanged` / `filesChanged` 事件自动刷新。

非目标（后续迭代）：多分支拓扑图线（`--all` 泳道图）、checkout/reset/cherry-pick 等写操作、远程 fetch 触发。

## Capabilities

### New Capabilities

- `git-history-pane`: Inspector 中的提交历史面板——历史列表的内容、装饰徽章、未提交/传出更改节点、展开详情、刷新时机与空态/错误态行为。

### Modified Capabilities

（无——现有能力尚无 spec，且本变更不修改现有面板的行为。）

## Impact

- `supacode/Clients/Git/GitClient.swift`：新增 commit log / commit detail 查询接口与解析。
- `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`：`WorktreeInspectorPane` 枚举加 `history` case；新增历史状态与加载 action。
- `supacode/Features/Repositories/Views/WorktreeStatusInspector.swift`：容器 switch 分发新 pane；新建历史视图文件。
- `supacode/Features/Repositories/Views/WorktreeStatusToolbarItems.swift` 与 `WorktreeDetailView.swift`：新增工具栏切换按钮。
- `supacode/Commands/SidebarCommands.swift`：新增菜单命令。
- 测试：`supacodeTests/` 新增 GitClient 解析测试与 reducer 测试（项目规则：reducer 逻辑变更必须加测试）。
- 无新第三方依赖；只读 git 操作，无数据迁移。
