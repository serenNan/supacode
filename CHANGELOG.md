# 变更日志

## 2026-07-12 内置待办面板（todo panel）
- 新增独立 Todos 窗口（Window 菜单 / ⌥⌘T）+ 侧边栏左下角常驻 Todos 按钮：显示当前会话项目 TODO.md 的未完成项，按标题分组；两个入口共用一套 reducer
- 侧边栏按钮点击后在按钮上方就地展开一个规整圆角矩形面板（非 popover、无箭头指示），激活时按钮主题色高亮；面板纯显示待办内容
- 勾选圆圈把 `- [ ]` 改成 `- [x]`（字节级保真+冲突保护），点任务文字把文本注入当前会话终端输入框（不回车）
- 文件解析顺序：当前 worktree 根目录 TODO.md 优先，缺失回退仓库主 checkout；kqueue watcher 200ms 去抖自动刷新；独立窗口与展开面板按呈现引用计数，最后一个关闭才拆 watcher
- OpenSpec change `add-todo-panel`；上游 PR 候选，cherry-pick 时剔除本文件与 openspec/

## 2026-07-12 菜单栏通知项（仿 cmux）
- 新增 macOS 菜单栏铃铛（`MenuBarExtra` `.menu` 样式），存在未读通知时图标变 `bell.badge`；下拉列出最近 ≤10 条未读（terminal 通知显示会话名/摘要/相对时间，issue 通知显示标题/仓库名），点击条目激活 app、选中 worktree、聚焦对应 surface 并标已读（issue 条目开 GitHub 并标已读）
- 菜单快捷操作：显示通知面板（激活主窗并开 inspector Notifications 页，已打开时不反向 toggle）/ 跳转到最新未读（复用 ⇧⌘U 逻辑）/ 全部标记为已读 / 全部清除（terminal + issue 一起清）；底部：检查更新 / 设置 / 退出
- 设置 → Notifications 新增 "Show menu bar icon" 开关（`GlobalSettings.showMenuBarIcon` 默认开，旧设置文件 `decodeIfPresent` 兼容；Cmd 拖出菜单栏图标也会同步关掉该设置）
- 踩坑记录：`MenuBarExtra(isInserted:)` 每次 scene 求值都会回写 binding，若走 BindingReducer 的 persist 路径会形成 scene→persist→scene 死循环把 app 启动卡死（测试宿主 hang 即此因）；改为专用 `setShowMenuBarIcon` action，reducer 与 App 侧 binding 双层同值去重
- 复用现有通知系统：数据源 `toolbarNotificationGroupsCache`（新增 `MenuBarNotificationList` 纯派生 + 抽取 headline 解析为 `WorktreeTerminalNotification.headline(sessionTitle:)` 供 inspector 共用）；manager 新增 `markAllNotificationsRead`/`dismissAllNotifications` 并经 TerminalClient 桥接
- 新增测试 17 条（MenuBarNotificationListTests 7、AppFeatureMenuBarNotificationsTests 6、设置解码/往返/binding/action 4）；OpenSpec 工件在 `openspec/changes/add-menu-bar-notifications/`

## 2026-07-12 通知面板按会话折叠
- 通知 inspector 里同一会话（tab）的多条通知默认折叠：只显示最新一条，其余收进 "Show N Older" 展开控件，点开内联显示完整历史；纯 UI 折叠，不删任何通知数据（区别于已 revert 的"每 tab 只留一条"23f768df）
- 折叠时若隐藏的旧通知里有未读，控件上带橙点 + "N unread" 提示，未读永不被折叠吞掉；铃铛计数语义不变
- 实现：ToolbarNotificationWorktreeGroup 增加 sessionClusters 计算属性（键 tabID，tab 已关时回退 surfaceID 归组），展开状态是 inspector 的临时 @State 不持久化；新增 3 个分组测试
- OpenSpec change：openspec/changes/collapse-notifications-by-session
- 去掉通知行 hover 弹出完整通知内容的行为（inspector 行与侧边栏 popover 两处）：折叠展开已能看历史全文，悬浮大段文本反而碍事；tooltip 回归纯动作提示（"Select worktree and focus terminal." / "Focus pane"）

## 2026-07-11 回合上游三个修复 PR + 测试 locale 修正
- cherry-pick 上游未合并的 bug 修复 PR（作者 jeremybower）：#639 tuist 重新生成只清本 worktree 的 DerivedData（挪到仓库内 `.build/DerivedData`，根治并行 worktree 构建互删）、#638 coalescesBurstOfProgressReports 改 advance-until-settled 循环去 flaky、#632 merge queue ETA 测试适配 macOS 26.5
- 在 #632 之上追加 fork 修正：surfacesPositionAndEstimatedTime 的分钟拼写既随 OS 版本也随 locale/地区变（作者 en_CA 26.5 出 "mins"，本机同版本出 "min"），版本判断修不干净；改为按同文件 formatsMultiUnitEstimate 先例断言形状+组合、不断言拼写。此测试在本机一直挂的根因即此（对应记忆里"date 依赖测试待修"）

## 2026-07-11 侧边栏行标题改为项目名（worktree 文件夹名）
- 行主标题不再显示分支名/会话标题：改为 worktree 文件夹名（主 worktree 即仓库文件夹名），自定义标题依旧最优先；会话标题只在展开的子行里显示
- 副标题改为分支名，统一中性次要色（去掉 main 黄 / pinned 橙的 accent 染色）；高亮区副标题在仓库名与主标题重复时去掉仓库标签只留分支（远程行保留 host 完整形式）
- 拆除第一轮"主标题跟随选中 tab 标题"整条链路（selectedTabTitle / sessionRowTitle / ResolvedRowDisplay.sessionTitle）及其测试；ResolvedRowDisplayTests 按新语义重写

## 2026-07-11 通知面板标题改为会话（tab）名
- 通知落库时记录所属 tab（WorktreeTerminalNotification.tabID），通知 inspector 里 agent 通知的标题从统一的 "Claude Code" 改为该通知所在标签页的实时标题，Claude Code `/rename` 或手动改 tab 名后已有通知行会跟着更新
- 实现：ToolbarNotificationWorktreeGroup 增加 tabTitles（只收录被通知引用的 tab，Equatable diff 对无关 tab 的标题风暴免疫）；tabsSnapshotChanged 的 cacheInvalidations 加 .toolbarNotificationGroups
- 兜底：tab 已关/标题空白回退 agent 显示名；tab 标题是裸进程名 "claude" 时映射回 "Claude Code"；非 agent 通知保留原始标题
- 新增 4 个测试（分组解析 / 无关标题变更不改分组 / 缓存失效映射 / 落库记 tabID）；此改动并入 #630 通知面板 PR 范围（提 PR 时从 upstream/main 切分支 cherry-pick，勿带 CHANGELOG）

## 2026-07-11 侧边栏子行选中加灰色背景高亮
- 展开的会话子行里，当前选中 tab 除加粗外增加圆角灰色背景（系统 unemphasizedSelectedContentBackgroundColor，非 accent 色——父行已有 accent 选中高亮），一眼可见当前所在子标签页

## 2026-07-11 侧边栏会话子行完善（agent 图标 + 整行点击展开）
- agent 出勤扇出按 tab 重分组（AppFeature.agentSnapshotEffects → 新 action tabAgentsChanged → SidebarItemFeature.State.tabAgents），展开的子行左侧图标换成该 tab 内运行 agent 的徽章（AgentAvatarGroupView，等待输入反色保留），无 agent 的 tab 保持默认图标；展开时父行聚合 agent 徽章隐藏，收起恢复
- 行标题区（不含行尾控件）加 simultaneousGesture 点击切换子行展开/收起，⌘/⇧ 多选点击跳过，chevron 按钮保留为显式控件
- 新增 SidebarItemFeatureTests.tabAgentsSnapshotReplacesWholesaleAndSkipsNoOps；并行会话构建互踩用独立 -derivedDataPath 隔离（比开 worktree 轻量）

## 2026-07-11 GitHub issue 追踪
- 状态检查器新增 Pull Request / Issues 分段切换：Issues 页列出仓库（fork 自动解析上游）最近更新的 50 个 open issue（编号、标题、标签、作者、评论数、相对时间），点击跳 GitHub
- issue 轮询搭 PR 刷新顺风车（同 30/60s 节奏、同 githubIntegrationEnabled 开关，无新任务表）；快照 diff 检测新 issue / 新评论 / 标签变化，推 repo 级通知到工具栏铃铛（首载静默），点通知开 issue 页并标已读
- 新增 GithubIssue 模型 + GithubCLIClient.listIssues（gh api graphql）、RepositoryIssueUpdates 纯 diff 逻辑、RepositoryIssuesInspectorView；OpenSpec 工件在 openspec/changes/add-issue-tracking/（验证后可 archive）
- 全量测试 2409 用例通过；此功能为 fork 自用，暂不走上游贡献流程
## 2026-07-11 通知面板紧凑化
- 通知 inspector 的正文截断为 3 行（WorktreeStatusInspector.swift NotificationRow 加 lineLimit(3)），悬停 tooltip 显示完整内容，点击跳转 pane 行为不变
- 此改动是上游 PR 候选，提 PR 时从 upstream/main 切分支 cherry-pick 此提交

## 2026-07-11 个人 fork 配置
- supacode.json：worktree 打开方式从 Xcode 改为 VS Code（openActionID）
- 本文件只存在于个人 fork（serenNan/supacode）的 main，给上游提 PR 时从 upstream/main 切分支，勿带上此文件
