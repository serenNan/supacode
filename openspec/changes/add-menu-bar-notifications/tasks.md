## 1. 可见性三态设置（TDD）

- [x] 1.1 `SupacodeSettingsShared` 新增 `AppVisibility` 枚举（`dock` / `dockAndMenuBar` / `menuBar`）+ 派生 `showsMenuBarIcon` / `hidesDockIcon`
- [x] 1.2 `GlobalSettings` 用 `appVisibility: AppVisibility`（默认 `dock`）替换 `showMenuBarIcon: Bool`；Codable 迁移旧字段（`showMenuBarIcon true→dockAndMenuBar / false→dock`，缺失→默认 dock）——先写解码迁移测试再实现
- [x] 1.3 `SettingsFeature`：`setAppVisibility` action（reducer 去重 guard 同值）替换 `setShowMenuBarIcon`，State 双向同步，补 reducer 测试

## 2. activation policy 接线

- [x] 2.1 `supacodeApp.swift`：`MenuBarExtra(isInserted:)` 绑定改为 `appVisibility.showsMenuBarIcon`（沿用去重 binding）
- [x] 2.2 `applicationDidFinishLaunching` + 可见性变化时应用 `NSApp.setActivationPolicy`（`menuBar → .accessory`，其余 `.regular`）；切回 `.regular` 后 `surfaceMainWindow()`

## 3. 按-worktree 关注清单（TDD）

- [x] 3.1 `MenuBarNotificationList` 改为派生 `[MenuBarWorktreeRow]`（worktreeID/repoName/worktreeName/unreadCount/hasActiveAgent），纳入 `unreadCount>0 || hasActiveAgent`，未读优先排序，`hasUnread` 标志——从 `toolbarNotificationGroupsCache` + agent 活跃集合派生，配单元测试
- [x] 3.2 `AppFeature`：`menuBarWorktreeSelected(worktreeID:)`（激活 app + `selectWorktree`）action，配 TestStore 测试；保留 `markAllNotificationsRead`

## 4. 菜单栏 UI 重构

- [x] 4.1 `MenuBarNotificationsLabel` 换成 SC monogram（代码渲染，template 适配明暗）+ 未读红点 badge
- [x] 4.2 `MenuBarNotificationsMenu` 重构：worktree 行（名/未读数/agent 标，点击 `menuBarWorktreeSelected`）、空态占位、"全部标记为已读"（`hasUnread` 禁用）、"显示主窗口"、"设置…"、"退出"；移除 issue 通知/检查更新/跳转最新未读/全部清除

## 5. 可见性设置卡片组

- [x] 5.1 新建 `AppVisibilityOptionCardView`（仿 `AppearanceOptionCardView`：图 + 标题 + 选中描边），三态图片（asset 或 SF Symbol 占位）
- [x] 5.2 `AppearanceSettingsView`（General）在 Editor section 前插入 header-less 可见性 section；移除 `NotificationsSettingsView` 旧的 `showMenuBarIcon` Toggle

## 6. 验证与收尾

- [x] 6.1 `make build-app` 通过；跑相关测试（GlobalSettings 迁移、SettingsFeature、MenuBarNotificationList、AppFeature worktree 选中）全绿
- [ ] 6.2 实机验证：三态切换（Dock 隐藏/恢复、主窗口可达）、SC 图标未读红点、点 worktree 行跳转、全部标记已读、显示主窗口；重启后设置保留
- [x] 6.3 更新 CHANGELOG；逐项对照 spec 场景
