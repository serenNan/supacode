## Why

Supacode 的通知目前只能在主窗口内查看（工具栏铃铛 inspector、sidebar popover），一旦窗口被遮挡或位于其他 Space，用户就看不到 agent 的完成/求确认通知。cmux 通过 macOS 菜单栏状态项提供了始终可见的通知入口；Supacode 应提供同等能力：右上角常驻图标 + 未读徽标 + 下拉通知列表与快捷操作。

## What Changes

- 新增 macOS 菜单栏状态项（`MenuBarExtra`），图标随未读状态变化（如 `bell` / `bell.badge`）
- 点击展开菜单，包含：
  - 未读通知列表（最近 N 条）：每条显示会话/tab 名、内容摘要、相对时间；点击跳转到对应 worktree/surface 并标记已读
  - 无未读时显示"没有未读通知"占位
  - 操作项：显示主窗口通知面板、跳转到最新未读（复用 `jumpToLatestUnread`）、全部标记为已读、全部清除
  - 常规项：检查更新、打开设置、退出 Supacode
- 新增设置开关 `showMenuBarIcon`（`GlobalSettings`），可在通知设置页里开关菜单栏图标
- 复用现有通知系统：数据来自 `toolbarNotificationGroupsCache` / `notificationIndicatorCount`，操作复用 `WorktreeTerminalManager` 已有的标记已读/清除/跳转能力，不引入新的通知存储

## Capabilities

### New Capabilities
- `menu-bar-notifications`: macOS 菜单栏状态项的展示（图标、未读徽标、通知列表）与交互（跳转、标记已读、清除、打开设置/更新/退出），及其启用开关

### Modified Capabilities

（无——现有通知产生、存储、面板行为的需求不变，仅新增消费入口）

## Impact

- `supacode/App/supacodeApp.swift`：新增 `MenuBarExtra` scene
- `supacode/Features/App/Reducer/AppFeature.swift`：新增菜单栏相关 action（或复用现有 `jumpToLatestUnread` / `selectWorktree` / dismiss 系列）
- `SupacodeSettingsShared/Models/GlobalSettings.swift` + `SupacodeSettingsFeature/`（`SettingsFeature.swift`、`NotificationsSettingsView.swift`）：新增 `showMenuBarIcon` 设置
- 新增菜单栏视图文件（Features/App 或独立目录）
- 无新第三方依赖；无数据迁移（新设置字段用 `decodeIfPresent` 向后兼容）
