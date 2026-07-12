## ADDED Requirements

### Requirement: 菜单栏状态项与未读徽标
应用 SHALL 在 macOS 菜单栏显示一个状态项，图标 MUST 反映未读通知状态：存在未读通知（terminal 或 issue）时显示带徽标的变体（`bell.badge`），否则显示普通变体（`bell`）。

#### Scenario: 收到新通知时图标变化
- **WHEN** 存在至少一条未读通知
- **THEN** 菜单栏图标显示 `bell.badge` 变体

#### Scenario: 全部已读后图标恢复
- **WHEN** 所有通知被标记已读或清除
- **THEN** 菜单栏图标恢复为普通 `bell` 变体

### Requirement: 通知列表菜单
点击状态项 SHALL 展开菜单，显示最近最多 10 条未读通知（新→旧）。每条 terminal 通知 MUST 显示会话/tab 名、内容摘要和相对时间；issue 通知 MUST 显示 issue 标题与仓库名。无未读通知时 MUST 显示禁用的"没有未读通知"占位项。

#### Scenario: 有未读通知时展开菜单
- **WHEN** 用户点击菜单栏图标且存在 3 条未读通知
- **THEN** 菜单顶部按时间倒序列出这 3 条，每条含会话名、摘要、相对时间

#### Scenario: 无未读通知时展开菜单
- **WHEN** 用户点击菜单栏图标且无未读通知
- **THEN** 菜单顶部显示禁用的"没有未读通知"占位项

#### Scenario: 超过 10 条未读
- **WHEN** 存在 12 条未读通知
- **THEN** 菜单只显示最新的 10 条

### Requirement: 点击通知跳转
点击菜单中的 terminal 通知 SHALL 激活应用、选中对应 worktree、聚焦对应 surface，并将该通知标记为已读。点击 issue 通知 SHALL 复用现有 issue 通知选中行为。

#### Scenario: 从后台点击通知
- **WHEN** 应用主窗口在后台，用户点击菜单中某条 terminal 通知
- **THEN** 应用被激活，对应 worktree 被选中，对应 surface 获得焦点，该通知变为已读

### Requirement: 菜单快捷操作
菜单 SHALL 提供以下操作项：显示通知（激活主窗口并打开通知面板）、跳转到最新未读（复用现有 jumpToLatestUnread，无未读时禁用）、全部标记为已读（无未读时禁用）、全部清除（无通知时禁用）。

#### Scenario: 全部标记为已读
- **WHEN** 存在多个 worktree 各有未读通知，用户点击"全部标记为已读"
- **THEN** 所有 worktree 的所有通知变为已读，菜单栏图标恢复普通变体

#### Scenario: 全部清除
- **WHEN** 存在 terminal 通知与 issue 通知，用户点击"全部清除"
- **THEN** 两类通知均被移除，通知面板与菜单均为空

#### Scenario: 跳转到最新未读
- **WHEN** 用户点击"跳转到最新未读"
- **THEN** 行为与现有 ⇧⌘U 快捷键一致

### Requirement: 应用级菜单项
菜单底部 SHALL 提供：检查更新、偏好设置（打开设置窗口）、退出 Supacode。

#### Scenario: 从菜单栏打开设置
- **WHEN** 用户点击"偏好设置…"
- **THEN** 设置窗口被打开并置前

### Requirement: 菜单栏图标开关
设置 SHALL 提供 `showMenuBarIcon` 开关（默认开启），关闭后状态项从菜单栏移除，重新开启后恢复。该设置 MUST 持久化，且旧版本设置文件缺失该字段时按默认值处理。

#### Scenario: 关闭菜单栏图标
- **WHEN** 用户在设置中关闭"在菜单栏显示图标"
- **THEN** 状态项立即从菜单栏消失

#### Scenario: 旧设置文件兼容
- **WHEN** 加载不含 `showMenuBarIcon` 字段的既有设置文件
- **THEN** 解码成功且该值为 true
