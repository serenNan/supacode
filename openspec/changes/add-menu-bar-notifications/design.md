## Context

通知系统已完整存在：
- 数据模型 `WorktreeTerminalNotification`（含 `isRead`）与 `RepositoryIssueNotification`，权威存储在 `WorktreeTerminalState.notifications`，TCA 投影在 `SidebarItemFeature.State`
- 聚合缓存 `RepositoriesFeature.State.toolbarNotificationGroupsCache`（由 `computeToolbarNotificationGroups()` 纯函数计算），供工具栏铃铛 inspector 使用
- 未读指示 `AppFeature.State.notificationIndicatorCount`（`.notificationIndicatorChanged` 事件维护）
- 已有操作：`jumpToLatestUnread`（AppFeature）、`markNotificationRead` / `latestUnreadNotificationLocation` / `dismissAllNotifications`（manager/state 层）、`selectToolbarNotification` 跳转链
- App 入口 `supacodeApp.swift` 全部为 `Window` scene，无任何 MenuBarExtra/NSStatusItem 代码

## Goals / Non-Goals

**Goals:**
- 菜单栏常驻通知入口：图标 + 未读徽标 + 下拉列表 + 快捷操作，主窗口不可见时也能触达
- 完全复用现有通知数据与操作路径，不新增通知存储
- 可通过设置开关显示/隐藏菜单栏图标

**Non-Goals:**
- 不改变通知的产生、去重、持久化行为
- 不做菜单栏内的富交互面板（搜索、分组折叠等）——v1 用原生菜单
- 不支持 LSUIElement（无 Dock 图标）模式
- 不在菜单栏项上显示未读数字文本（仅图标变体区分）

## Decisions

**D1: `MenuBarExtra` scene（`.menu` 样式）而非 AppDelegate 手建 `NSStatusItem`**
SwiftUI `MenuBarExtra` 与现有全 SwiftUI scene 结构一致，`isInserted:` binding 天然支持设置开关，无需手动管理 NSStatusItem 生命周期。`.menu` 样式得到原生 NSMenu 外观（与 cmux 截图一致），系统处理展开/收起/键盘导航。备选 `.window` 样式可做富 UI，但需自管尺寸与 dismiss，v1 不需要。

**D2: 不新建 MenuBarFeature reducer，菜单视图直接观察根 store**
菜单内容全部可从现有 state 派生（`repositories.toolbarNotificationGroupsCache`），操作大多已有对应 action。仅在 AppFeature 上补少量新 action（见 D4），避免为纯展示入口引入 Scope/State 样板。菜单视图放 `supacode/Features/App/Views/MenuBarNotificationsMenu.swift`。

**D3: 徽标与列表同源——都从 `toolbarNotificationGroupsCache` 派生**
图标 `bell` / `bell.badge` 取决于 cache 中是否存在未读（terminal + issue 通知统一计），与菜单列表内容一致，避免 `notificationIndicatorCount`（只计 terminal 通知的 worktree 数）与列表不同步的错位。列表显示最近 10 条未读，新→旧排序；terminal 通知条目显示会话/tab 名（复用 inspector 的 headline 解析逻辑，抽为共享 helper）+ 摘要 + 相对时间。

**D4: AppFeature 新增 action（配测试）**
- `menuBarNotificationSelected(worktreeID:surfaceID:notificationID:)`：激活 app + 选中 worktree + focus surface + 标记已读（复用 `jumpToLatestUnread` 的 effect 组合方式）
- `menuBarIssueNotificationSelected(...)`：转发到现有 `repositories.issueNotificationSelected`
- `markAllNotificationsRead`：经 TerminalClient 桥接 manager 遍历所有 worktree 调 `markAllNotificationsRead()`（新桥接方法）
- `clearAllNotifications`：桥接 `dismissAllNotifications()`（terminal）+ 转发 `repositories.dismissAllIssueNotifications`（issue）
- "显示通知"复用现有打开主窗口 + 通知 inspector 的机制；"跳转到最新未读"直接发既有 `jumpToLatestUnread`
- "检查更新"发 updates feature 既有 action；"偏好设置"用 `@Environment(\.openWindow)` 开 `WindowID.settings`；"退出"用 `NSApplication.shared.terminate`

**D5: 设置开关 `showMenuBarIcon: Bool`（默认 true）**
加在 `GlobalSettings`（default/init/Codable 用 `decodeIfPresent` 向后兼容），`SettingsFeature` binding 同步，UI 放 `NotificationsSettingsView` 的 Section。`MenuBarExtra(isInserted:)` 绑定该值。

## Risks / Trade-offs

- [`.menu` 样式对多行/副标题渲染受限] → 条目 label 用 title + subtitle 两个 `Text`（AppKit 菜单原生支持副标题）；若实测截断不佳，退化为单行 "会话名 — 摘要"。菜单不追求 inspector 的 3 行 hover 全文
- [菜单从后台激活主窗口需显式 `NSApp.activate`] → 在 selected/显示通知路径统一先激活再 focus，实机验证 Space 切换行为
- [cache 只在 repositories post-reduce 更新，菜单打开瞬间可能读到旧值] → 可接受：通知事件本身会触发 reduce，误差在毫秒级
- [`isInserted` 关闭后设置入口只剩主窗口] → 默认值 true，且开关文案说明位置
