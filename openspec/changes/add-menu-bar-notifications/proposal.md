## Why

Supacode 的通知目前只能在主窗口内查看（工具栏铃铛 inspector、sidebar popover），窗口被遮挡或位于其他 Space 时用户就看不到 agent 的完成/求确认状态。cmux 通过 macOS 菜单栏状态项提供始终可见的入口。上游维护者在 #645 中敲定了最终形态，并要求与 #623（隐藏 Dock 图标、让 Supacode 变纯菜单栏应用）合并处理，避免在菜单栏这块 UI 上反复迭代。

本 change 同时满足 #645 与 #623：把"是否显示菜单栏图标"从一个布尔开关升级为 **Dock / Dock & Menu Bar / Menu Bar 三态可见性**，并把菜单栏下拉从"复述通知内容"改为"列出正需要关注的 worktree"。

## What Changes

- **可见性三态**：用 `AppVisibility` 枚举（`dock` / `dockAndMenuBar` / `menuBar`，默认 `dock`）替换现有的 `showMenuBarIcon: Bool`。`menuBar` 模式经 `NSApp.setActivationPolicy(.accessory)` 隐藏 Dock 图标（应用当前无任何 Dock/activation-policy 机制），`dock` / `dockAndMenuBar` 为 `.regular`。三态保证"至少启用一个"。
- **图标换成 SC monogram**：菜单栏图标不再用 `bell`（与 Supacode 无直接关联），改为代码渲染的 SC 字母组合；存在未读时叠加小红点 badge。
- **下拉列表改为按-worktree 的关注清单**：不再复述通知消息（系统通知已负责内容），改为列出 **有未读通知或 agent 正活跃** 的 worktree，每行显示 worktree 名、未读数、agent 活跃标；点击激活应用并选中该 worktree。无内容时显示占位项。
- **菜单操作精简**：移除 issue 通知项与"检查更新"；新增"显示主窗口（Show Main Window）"；保留"全部标记为已读"、"设置…"、"退出"。去掉"跳转到最新未读"与"全部清除"。
- **设置 UI**：在 General（`AppearanceSettingsView`）的 Editor section 之前插入一个 header-less section，仿 `AppearanceOptionCardView` 的图片卡片组做三态可见性选择器。移除 `NotificationsSettingsView` 里旧的"在菜单栏显示图标"Toggle。

## Capabilities

### New Capabilities
- `menu-bar-notifications`: macOS 菜单栏状态项的可见性三态（含隐藏 Dock）、SC 图标与未读徽标、按-worktree 的 active/unread 关注清单及其交互（跳转、全部标记已读、显示主窗口、设置、退出）

## Impact

- `supacode/App/supacodeApp.swift`：`MenuBarExtra(isInserted:)` 绑定改为"可见性含菜单栏"；启动与可见性变化时按模式设置 `NSApp.setActivationPolicy`
- `supacode/Features/App/Views/MenuBarNotificationsMenu.swift`：菜单重构（worktree 清单 + 精简操作）；`MenuBarNotificationsLabel` 换成 SC monogram + 红点
- `supacode/Features/App/Models/MenuBarNotificationList.swift`：改为派生 active/unread 的 worktree 行
- `supacode/Features/App/Reducer/AppFeature.swift`：新增/调整 action（选中 worktree、显示主窗口）；移除 issue/清除/跳转相关的菜单专用分支
- `SupacodeSettingsShared/Models/GlobalSettings.swift`：`AppVisibility` 枚举替换 `showMenuBarIcon`，Codable 迁移旧字段
- `SupacodeSettingsFeature/`：`SettingsFeature.swift`（action + 同步）、`AppearanceSettingsView.swift`（新卡片组 section）、`NotificationsSettingsView.swift`（移除旧 Toggle）；新增可见性卡片视图
- 无新第三方依赖；无数据迁移风险（新字段用 `decodeIfPresent`，缺失时按旧 `showMenuBarIcon` 或默认值映射）

## Out of Scope

- Dock badge（在 Dock 图标上显示未读数）——维护者建议另开 issue + PR，本 change 不做
