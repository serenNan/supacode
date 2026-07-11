## Context

Notifications live per-worktree on `WorktreeTerminalState.notifications` (newest first), are projected into `SidebarItemFeature.State.notifications`, and are assembled for the inspector by `RepositoriesFeature.State.computeToolbarNotificationGroups()` into `ToolbarNotificationRepositoryGroup` → `ToolbarNotificationWorktreeGroup`, cached on `toolbarNotificationGroupsCache`. `NotificationsInspectorContent` renders one flat `ForEach(worktree.notifications)` per worktree section. Each notification carries an optional `tabID` (added with the session-title feature); `surfaceID` is always present.

The reverted "one per tab" commit (23f768df) removed older same-tab notifications at append time — right noise reduction, wrong layer. This change reproduces the reduction at the presentation layer only.

## Goals / Non-Goals

**Goals:**
- Sessions with multiple notifications occupy one row by default (newest), with inline expansion to full history.
- Hidden unread notifications stay discoverable (hint on the expand control).
- Grouping logic is a pure, unit-testable state computation.

**Non-Goals:**
- No changes to notification storage, append, dismissal, or read-marking.
- No changes to the sidebar popover (`NotificationPopoverView`) — it shows per-worktree notifications on hover and is out of scope.
- No persistence of expansion state.
- No cap/expiry of notification history (separate concern).

## Decisions

1. **Cluster in `computeToolbarNotificationGroups()`, not in the view.**
   `ToolbarNotificationWorktreeGroup` gains `sessionClusters: [NotificationSessionCluster]`, computed where the group is built and carried through the existing cache. Rationale: keeps view bodies dumb (project convention: views render cached structures), makes ordering/fallback rules unit-testable in `ToolbarNotificationGroupingTests`, and reuses the existing cache invalidation (`terminalProjectionChanged`, `tabsSnapshotChanged`). Alternative — grouping in the view body with `Dictionary(grouping:)` — rejected: recomputes per render and can't be tested without a view host.

2. **Cluster key: `tabID` when present, else `surfaceID`.**
   `enum NotificationSessionKey: Hashable { case tab(TerminalTabID), surface(UUID) }`. A notification whose tab was already gone at append time still groups with its surface siblings instead of degrading to one row each.

3. **Cluster order and content order both follow the existing newest-first array.**
   Clusters sort by their newest notification (stable with the current insert-at-0 ordering); within a cluster, notifications keep newest-first. The collapsed row is the cluster's first element — the same row the flat list would have shown on top.

4. **Expansion is `@State` in the inspector content view.**
   `@State private var expandedClusters: Set<NotificationSessionKey>`. Transient by design; a pane switch or relaunch resets to collapsed. Alternative — reducer state — rejected: no other feature reads it, and per-toggle actions through the store would re-run the post-reduce hooks for a purely visual toggle.

5. **Expand control is a row-level borderless button below the newest row: "Show N Older" / "Hide Older", with an unread hint.**
   When collapsed and any hidden notification is unread, the control shows the hidden-unread count (e.g. orange dot + count) so unread state never disappears from view. Buttons get `.help` tooltips per UX standards.

## Risks / Trade-offs

- [Clusters recompute on every cache rebuild] → the computation is O(n) over an already-materialized array per worktree; same complexity class as the existing `notificationTabTitles`.
- [Equatable growth on `ToolbarNotificationWorktreeGroup`] → clusters derive solely from `notifications` + `tabID`s already in the struct, so the Equatable diff surface doesn't gain new churn sources.
- [Expansion state keyed by tab may outlive the tab] → keys of gone tabs simply stop matching any cluster; the set is bounded by user clicks and reset on view teardown.
- [`Form`/`Section` row identity changes when a cluster expands] → use stable per-notification `id`s inside `ForEach` so SwiftUI diffing stays cheap; verify no animation glitches manually.
