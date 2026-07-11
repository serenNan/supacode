# 变更日志

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
