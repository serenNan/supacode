## 1. 设置开关 showMenuBarIcon

- [x] 1.1 `GlobalSettings` 新增 `showMenuBarIcon: Bool`（默认 true；同步 default/init/Codable `decodeIfPresent`），先写解码兼容测试再实现
- [x] 1.2 `SettingsFeature.State` 增加 binding 字段并与 `GlobalSettings` 双向同步（load/emit），补 reducer 测试
- [x] 1.3 `NotificationsSettingsView` 增加"在菜单栏显示图标"Toggle（带 tooltip）

## 2. 数据派生与桥接

- [x] 2.1 从 `toolbarNotificationGroupsCache` 派生菜单数据的纯函数（最近 ≤10 条未读、新→旧、terminal/issue 混排、hasUnread 标志；会话名 headline 解析复用/抽取 inspector 现有逻辑为共享 helper），配单元测试
- [x] 2.2 `WorktreeTerminalManager` 新增 `markAllNotificationsRead()`（遍历全部 worktree）并经 `TerminalClient` 桥接暴露；`dismissAllNotifications` 同样桥接（如尚未暴露）

## 3. AppFeature 新 action（TDD）

- [x] 3.1 `menuBarNotificationSelected`：激活 app + `selectWorktree` + `focusSurface` + `markNotificationRead`（仿 `jumpToLatestUnread` effect 组合），先写 TestStore 测试
- [x] 3.2 `markAllNotificationsRead` / `clearAllNotifications`（terminal 桥接 + 转发 `repositories.dismissAllIssueNotifications`），配 TestStore 测试
- [x] 3.3 "显示通知"action：激活主窗口并打开通知 inspector（复用现有 inspector 展示 state），配测试

## 4. 菜单栏 UI

- [x] 4.1 新建 `MenuBarNotificationsMenu` 视图：通知条目（会话名/摘要/相对时间，issue 条目显示 issue 标题/仓库）、空态占位、"显示通知/跳转到最新未读/全部标记为已读/全部清除"（按 hasUnread/hasAny 禁用）、分隔线、"检查更新…/偏好设置…/退出 Supacode"
- [x] 4.2 `supacodeApp.swift` 新增 `MenuBarExtra` scene（`.menu` 样式，图标 `bell`/`bell.badge` 随未读切换，`isInserted:` 绑定 `showMenuBarIcon`）

## 5. 验证与收尾

- [x] 5.1 `make build-app` 通过；跑相关测试套件（supacodeTests: SettingsFilePersistence/SettingsFeature/MenuBarNotificationList；supacodeFeatureTests: AppFeatureMenuBarNotifications/AppFeatureJumpToLatestUnread 全绿）
- [ ] 5.2 实机验证：收通知→图标变徽标→点击条目从后台跳转正确 surface 并标已读；全部标已读/清除同步 inspector；开关设置即时生效；重启后设置保留
- [x] 5.3 更新 CHANGELOG（如项目惯例要求）并逐项确认 spec 场景
