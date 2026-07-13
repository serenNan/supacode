## Context

现有基础：
- 通知系统完整存在：`WorktreeTerminalNotification`（含 `isRead`）、聚合缓存 `RepositoriesFeature.State.toolbarNotificationGroupsCache`、桥接方法 `markAllNotificationsRead()`。
- Agent presence 已被追踪：`AppFeature.State.agentPresence`，`agentsBySurface()` 给出每个 surface 的活跃 agent；surface 可映射回 worktree。
- 上一版菜单栏功能已在 fork 实现（`MenuBarExtra` `.menu` 样式、`MenuBarNotificationsMenu` / `MenuBarNotificationsLabel`、`showMenuBarIcon: Bool`、AppFeature 的 `menuBarNotificationSelected` / `markAllNotificationsRead` / `clearAllNotifications` / `showNotificationsPane` 等 action）。本 change 是对它的重设计。
- 应用当前**没有**任何 Dock/activation-policy 控制（`grep setActivationPolicy | LSUIElement` 在 app target 零命中；Info.plist 无 `LSUIElement`）。
- General 设置页实际是 `AppearanceSettingsView`（`.navigationTitle("General")`），`Form { }.formStyle(.grouped)`，Editor section 在 body 中段；Appearance 用自定义卡片组 `AppearanceOptionCardView`（`Image(mode.imageName)` asset 图 + 选中描边），非 segmented Picker。

## Goals / Non-Goals

**Goals**
- 菜单栏常驻入口 + 可隐藏 Dock 的三态可见性，一套设置同时解决 #645 与 #623
- 下拉聚焦"哪些 worktree 需要关注"（unread 或 agent 活跃），点击即跳转
- 完全复用现有通知数据、agent presence 与选中 worktree 的路径，不新增存储

**Non-Goals**
- 不改变通知的产生、去重、持久化行为
- 不做菜单栏内富交互面板（v1 用原生 `.menu`）
- 不在图标上显示未读数字文本（仅红点区分）
- 不做 Dock badge（另开）

## Decisions

**D1: `AppVisibility` 三态枚举替换 `showMenuBarIcon: Bool`**
`public enum AppVisibility: String { case dock, dockAndMenuBar, menuBar }`，放 `SupacodeSettingsShared`。派生 helper：`showsMenuBarIcon`（`dockAndMenuBar || menuBar`）、`hidesDockIcon`（`== menuBar`）。默认 `dock`（贴合维护者 "Dock enabled by default"：菜单栏 opt-in）。
Codable 迁移：先 `decodeIfPresent(AppVisibility, forKey: .appVisibility)`；缺失时读旧 `showMenuBarIcon`（`true → dockAndMenuBar`、`false → dock`）；再缺失用默认 `dock`。旧字段仅解码、不再编码。迁移一致性：只有显式 `showMenuBarIcon == true` 的用户拿到菜单栏；其余（含缺失=菜单栏功能之前的老文件）都是 Dock-only。

**D2: activation policy 接线在 App 层**
`supacodeApp.swift` 新增一处 `applyActivationPolicy(for:)`：`menuBar → .accessory`，其余 `→ .regular`。在 `applicationDidFinishLaunching` 应用一次，并在可见性设置变化时再应用（观察 `store.settings.appVisibility`）。从 `.accessory` 切回 `.regular` 后调用现有 `NSApplication.surfaceMainWindow()` 保证主窗口可达。`MenuBarExtra(isInserted:)` 绑定 `appVisibility.showsMenuBarIcon`，沿用现有"只在真正翻转时才写 store"的去重 binding，避免 scene→persist→scene 死循环（上一版踩过）。

**D3: 下拉数据 = 按-worktree 的 active/unread 行**
`MenuBarNotificationList`（保留文件名，语义改为 worktree 关注清单）纯函数从 `toolbarNotificationGroupsCache`（未读数）+ agent 活跃集合（由 `agentsBySurface()` 归约到 worktree）派生 `[MenuBarWorktreeRow]`：字段 `worktreeID` / `repoName` / `worktreeName` / `unreadCount` / `hasActiveAgent`。纳入条件：`unreadCount > 0 || hasActiveAgent`。排序：未读优先、再按最近通知时间。空集合时菜单显示占位项。`hasUnread` 标志供"全部标记已读"禁用态。

**D4: AppFeature action 调整**
- 复用现有"选中 worktree + 激活 app"路径做行点击（`menuBarWorktreeSelected(worktreeID:)`：`NSApp.activate` + `repositories.selectWorktree`）。
- 保留 `markAllNotificationsRead`（经 TerminalClient 桥接）。
- 新增/复用"显示主窗口"：直接 `NSApplication.surfaceMainWindow()`（App 已有），菜单项走一个轻 action 或直接在 view 调用。
- 移除菜单对 `issueNotificationSelected` / `clearAllNotifications` / `jumpToLatestUnread` / `updates(.checkForUpdates)` 的使用（action 本身若他处仍用则保留，仅从菜单摘除）。

**D5: SC monogram 图标**
`MenuBarNotificationsLabel` 用代码渲染 SC 字母组合（`Text("SC")` + `.font(.system(..., weight:.bold, design:.rounded))`，或 `Label`/`Canvas`），template 渲染以适配菜单栏明暗；`hasUnread` 时右上叠加 `Circle().fill(.red)` 小红点。无需新增 asset。

**D6: 设置卡片组**
新建 `AppVisibilityOptionCardView`（仿 `AppearanceOptionCardView`：图 + 标题 + 选中描边）。三态图片：优先复用/新增 asset（dock、dock+menubar、menubar 示意）；若无 asset 则以 SF Symbol 组合占位（`dock.rectangle` / `menubar.rectangle` 等），标题 `Dock` / `Dock & Menu Bar` / `Menu Bar`。放 `AppearanceSettingsView` 的 Editor section 之前，header-less `LabeledContent("Visibility") { HStack{cards} }` 或独立 Section。移除 `NotificationsSettingsView` 的旧 Toggle。

## Risks / Trade-offs

- [`.accessory` 后无 Dock 图标，用户找不回主窗口] → `menuBar` 模式保证菜单栏图标常显，菜单含"显示主窗口"；切回 `.regular` 主动 surface。
- [切 activation policy 时机] → 在 launch + 设置变化两处应用；避免在每次 scene 求值时调用（会抖动）。
- [SC monogram 在菜单栏渲染尺寸/对齐] → 实机核对明暗与红点位置；维护者已认可"SC 变体先够用"。
- [卡片组缺 asset] → 先用 SF Symbol 占位，后续可替换真图；不阻塞功能。
- [默认 `dock`（菜单栏 opt-in）] → 契合维护者 "Dock enabled by default"；新装用户不会平白多个菜单栏图标。
