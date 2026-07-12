## 1. Session clustering (model, TDD)

- [x] 1.1 Red: add failing tests in `ToolbarNotificationGroupingTests` — same-tab notifications cluster together newest-first, nil-`tabID` notifications cluster by `surfaceID`, clusters order by newest notification, single-notification cluster shape
- [x] 1.2 Green: add `NotificationSessionKey` and `NotificationSessionCluster`, populate `ToolbarNotificationWorktreeGroup.sessionClusters` in `computeToolbarNotificationGroups()`
- [x] 1.3 Red→Green: unread accounting on a cluster (hidden-unread count for the expand hint) with tests

## 2. Inspector collapse UI

- [x] 2.1 Render clusters in `NotificationsInspectorContent`: collapsed shows newest row; expand control ("Show N Older" / "Hide Older", `.help` tooltips) toggles per-cluster `@State`; single-notification clusters render as today
- [x] 2.2 Unread hint on collapsed clusters that hide unread notifications

## 3. Verification

- [x] 3.1 Run `supacodeTerminalTests` + `ToolbarNotificationGroupingTests` bundles; all green
- [x] 3.2 Build the app (direct `xcodebuild`, not `make`) and manually verify collapse/expand + bell badge unchanged
- [x] 3.3 Commit on branch `通知功能完善`
