## Why

A busy agent session emits several near-duplicate notifications in a row, so the notifications inspector fills up with entries from the same session and drowns out other worktrees. The earlier "keep one notification per tab" fix solved the noise but deleted history and was reverted (f9ee6afe); we still need the noise reduction, without discarding data.

## What Changes

- Group each worktree's notifications by session (tab) inside the notifications inspector.
- A session with multiple notifications renders collapsed by default: only its newest notification shows, with a "Show N Older" control that expands the full history inline.
- The expand control hints at hidden unread notifications so collapsed rows can't silently hide unread state.
- Pure presentation change: no notification data is deleted or mutated; unread counting (toolbar bell badge, sidebar dots) keeps its current semantics.
- Notifications without a `tabID` (tab already closed at append time, or pre-`tabID` records) fall back to grouping by `surfaceID`.
- Expansion state is transient view state; it is not persisted across app launches or pane switches.

## Capabilities

### New Capabilities
- `notification-session-collapse`: Session-grouped collapse/expand behavior of the notifications inspector list.

### Modified Capabilities
<!-- none: no existing spec in openspec/specs/ covers the notifications inspector -->

## Impact

- `supacode/Features/Repositories/Models/ToolbarNotificationGroup.swift`: `ToolbarNotificationWorktreeGroup` gains precomputed session clusters (computed in `computeToolbarNotificationGroups()`, cached on `toolbarNotificationGroupsCache`).
- `supacode/Features/Repositories/Views/WorktreeStatusInspector.swift`: `NotificationsInspectorContent` renders clusters with per-cluster expansion `@State`.
- `supacodeTests/ToolbarNotificationGroupingTests.swift`: new grouping tests.
- No reducer actions, persistence, or notification storage changes.
