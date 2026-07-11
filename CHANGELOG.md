# 变更日志

## 2026-07-11 通知面板标题改为会话（tab）名
- 通知落库时记录所属 tab（WorktreeTerminalNotification.tabID），通知 inspector 里 agent 通知的标题从统一的 "Claude Code" 改为该通知所在标签页的实时标题，Claude Code `/rename` 或手动改 tab 名后已有通知行会跟着更新
- 实现：ToolbarNotificationWorktreeGroup 增加 tabTitles（只收录被通知引用的 tab，Equatable diff 对无关 tab 的标题风暴免疫）；tabsSnapshotChanged 的 cacheInvalidations 加 .toolbarNotificationGroups
- 兜底：tab 已关/标题空白回退 agent 显示名；tab 标题是裸进程名 "claude" 时映射回 "Claude Code"；非 agent 通知保留原始标题
- 新增 4 个测试（分组解析 / 无关标题变更不改分组 / 缓存失效映射 / 落库记 tabID）；此改动并入 #630 通知面板 PR 范围（提 PR 时从 upstream/main 切分支 cherry-pick，勿带 CHANGELOG）

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
