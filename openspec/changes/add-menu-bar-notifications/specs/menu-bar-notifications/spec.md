## ADDED Requirements

### Requirement: 应用可见性三态

应用 SHALL 提供 `Dock` / `Dock & Menu Bar` / `Menu Bar` 三种可见性模式，并保证至少启用一处入口。`Menu Bar` 模式下应用 MUST 隐藏 Dock 图标（`NSApp.setActivationPolicy(.accessory)`），`Dock` 与 `Dock & Menu Bar` 模式 MUST 为 `.regular`。菜单栏状态项 MUST 在 `Dock & Menu Bar` 或 `Menu Bar` 模式下显示，在 `Dock` 模式下移除。该设置 MUST 持久化。

#### Scenario: 切换到 Menu Bar 隐藏 Dock

- **WHEN** 用户将可见性设为 `Menu Bar`
- **THEN** Dock 图标消失（activation policy 变为 `.accessory`），菜单栏状态项保持显示

#### Scenario: 切换到 Dock 移除菜单栏图标

- **WHEN** 用户将可见性设为 `Dock`
- **THEN** 菜单栏状态项立即从菜单栏消失，Dock 图标保留

#### Scenario: 从 Menu Bar 切回后主窗口可达

- **WHEN** 用户从 `Menu Bar` 切换到含 Dock 的模式
- **THEN** activation policy 恢复 `.regular` 且主窗口可被 surface

#### Scenario: 旧设置文件迁移

- **WHEN** 加载不含可见性字段但含旧 `showMenuBarIcon` 的设置文件
- **THEN** `showMenuBarIcon == true` 映射为 `Dock & Menu Bar`，`false` 映射为 `Dock`；两字段都缺失时按默认 `Dock` 处理（菜单栏 opt-in）

### Requirement: 可见性设置界面

General 设置页 SHALL 在 Editor section 之前提供一个可见性选择器，以图片卡片组（仿 Appearance 卡片）呈现 `Dock` / `Dock & Menu Bar` / `Menu Bar` 三选一，当前选中项 MUST 有视觉高亮。

#### Scenario: 在 General 选择可见性

- **WHEN** 用户在 General 设置页点击某个可见性卡片
- **THEN** 该卡片高亮，应用可见性立即切换并持久化

### Requirement: 菜单栏状态项图标

菜单栏状态项 SHALL 使用 SC monogram 图标（而非铃铛）。存在未读通知时图标 MUST 叠加红点徽标；无未读时 MUST 为不带徽标的普通 SC 图标。

#### Scenario: 有未读时显示红点

- **WHEN** 存在至少一条未读通知
- **THEN** 菜单栏 SC 图标叠加红点徽标

#### Scenario: 全部已读后红点消失

- **WHEN** 所有通知被标记已读或清除
- **THEN** 菜单栏图标恢复为不带红点的 SC 图标

### Requirement: 按-worktree 关注清单

点击状态项 SHALL 展开菜单，顶部列出**有未读通知或有活跃 agent** 的 worktree。每行 MUST 显示 worktree 名（及所属仓库）、未读数、以及 agent 活跃标识。未读的 worktree MUST 排在前。没有任何需关注的 worktree 时 MUST 显示禁用的占位项。

#### Scenario: 列出需关注的 worktree

- **WHEN** worktree A 有 2 条未读、worktree B 有活跃 agent 但无未读
- **THEN** 菜单顶部列出 A 与 B，A 显示未读数 2，B 显示 agent 活跃标，A 排在 B 前

#### Scenario: 无需关注项时的占位

- **WHEN** 没有任何 worktree 未读或有活跃 agent
- **THEN** 菜单顶部显示禁用的占位项（如"没有需要关注的会话"）

### Requirement: 点击行跳转 worktree

点击菜单中的 worktree 行 SHALL 激活应用并选中该 worktree。

#### Scenario: 从后台点击行

- **WHEN** 应用主窗口在后台，用户点击菜单中某个 worktree 行
- **THEN** 应用被激活，对应 worktree 在侧边栏被选中

### Requirement: 菜单快捷操作

菜单 SHALL 提供：全部标记为已读（无未读时禁用）、显示主窗口、设置、退出 Supacode。菜单 MUST NOT 再包含 issue 通知项、检查更新、跳转到最新未读、全部清除。

#### Scenario: 全部标记为已读

- **WHEN** 存在多个 worktree 各有未读，用户点击"全部标记为已读"
- **THEN** 所有 worktree 通知变为已读，菜单栏图标红点消失，该项变为禁用

#### Scenario: 显示主窗口

- **WHEN** 用户在 `Menu Bar` 模式下点击"显示主窗口"
- **THEN** 主窗口被置前显示

#### Scenario: 打开设置

- **WHEN** 用户点击"设置…"
- **THEN** 设置窗口被打开并置前
