# 变更日志

## 2026-07-11 通知面板紧凑化
- 通知 inspector 的正文截断为 3 行（WorktreeStatusInspector.swift NotificationRow 加 lineLimit(3)），悬停 tooltip 显示完整内容，点击跳转 pane 行为不变
- 此改动是上游 PR 候选，提 PR 时从 upstream/main 切分支 cherry-pick 此提交

## 2026-07-11 个人 fork 配置
- supacode.json：worktree 打开方式从 Xcode 改为 VS Code（openActionID）
- 本文件只存在于个人 fork（serenNan/supacode）的 main，给上游提 PR 时从 upstream/main 切分支，勿带上此文件
