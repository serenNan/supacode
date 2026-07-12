## 1. GitClient 数据层（TDD：先测试后实现）

- [x] 1.1 定义 `GitCommitSummary` / `GitCommitDetail` 模型（hash、shortHash、author、date、decorations、subject；detail 加 body、email、文件 numstat 列表）
- [x] 1.2 写 `GitClient.parseCommitLog(_:)` 纯函数解析测试：常规多条记录、`%D` 各形态（空、`HEAD -> main, origin/main`、`tag: v1`、detached HEAD）、emoji/多行消息、空仓库输出
- [x] 1.3 实现 `parseCommitLog` 与 `GitClient.commitHistory(at:limit:)`（`git log --first-parent -n 200 --format=%H%x1f…%x1e` + `rev-parse @{upstream}` + `rev-list --count @{upstream}..HEAD`，upstream 缺失时 aheadCount = 0）
- [x] 1.4 写 `GitClient.parseCommitDetail(_:)` numstat 解析测试（含 binary 文件 `-` 行、重命名路径），实现 `commitDetail(at:hash:)`
- [x] 1.5 验证 `runGit` 对 `WorktreeLocation.remote` worktree 的行为；不支持则在 history 查询入口对 remote 短路返回"不可用"标记（设计 Open Question 收口）

## 2. Reducer 状态与刷新（TDD）

- [x] 2.1 `WorktreeInspectorPane` 加 `case history`；`RepositoriesFeature.State` 加 `gitHistory: GitHistoryState?`
- [x] 2.2 新建 `RepositoriesFeature+GitHistory.swift`：`gitHistoryLoaded` / `gitHistoryFailed` / `expandCommit` / `commitDetailLoaded` / `refreshGitHistory` action 与 reduce 逻辑，effect 带固定 cancel ID
- [x] 2.3 Reducer 测试：打开 history pane 触发加载；pane 关闭时 watcher 事件不触发查询；切换 worktree 取消在途查询并重查；加载失败进入错误态、Retry 重查（用 TestClock / 受控依赖）
- [x] 2.4 接线刷新来源：`toggleInspectorPane` / `setInspectorPresented` / 选中变化 post-reduce / 拦截选中行 `branchChanged` + `diffStatsChanged`，全部收敛到 `refreshGitHistoryIfVisible`
- [x] 2.5 展开详情测试与实现：点击行懒加载 `commitDetail`，同一时刻只保留一条展开，重复点击收起

## 3. 视图

- [x] 3.1 新建 `WorktreeGitHistoryInspectorView.swift`：标题栏（History + 刷新按钮）+ `Form.grouped` 列表骨架，空态（folder / 空仓库 / remote 不可用）与错误态 + Retry
- [x] 3.2 提交行：图点连线列（首行未提交节点空心圆）、subject、作者、相对时间（`TimelineView(.everyMinute)`）、ref 徽章胶囊（HEAD 分支加粗）
- [x] 3.3 「Outgoing」Section 分组与「Uncommitted Changes」顶部节点（复用 `selectedWorktreeSlice` 的 added/removed）、截断 footer
- [x] 3.4 展开详情区：完整消息（可选中）、作者/绝对时间/hash、文件 +/- 列表（monospaced 绿红）；右键菜单 Copy Hash / Copy Message
- [x] 3.5 `WorktreeStatusInspectorContainer` switch 加 `.history` 分支

## 4. 入口三件套

- [x] 4.1 `WorktreeGitHistoryToolbarButton` 加入 `WorktreeStatusToolbarItems.swift`，接入 `WorktreeDetailView.TrailingStatusToolbarContent`（tint/foreground/tooltip+快捷键提示与现有按钮一致）
- [x] 4.2 `AppShortcuts` 加 `toggleHistoryInspector`；`SidebarCommands.swift` 加 View 菜单项（走既有 `toggleInspectorPaneAction`）

## 5. 验证收尾

- [x] 5.1 跑全部相关测试通过；`make build-app` 成功
- [ ] 5.2 `make run-app` 目验：打开 pane、看到本仓库提交历史 + main/origin/main 徽章 + 未提交节点、展开详情、切 worktree 刷新、工具栏不拥挤
