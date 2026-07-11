## ADDED Requirements

### Requirement: Session clustering of worktree notifications
The notifications inspector SHALL group each worktree's notifications into session clusters keyed by the notification's `tabID`, falling back to `surfaceID` when `tabID` is nil. Clusters SHALL be ordered by their newest notification (newest cluster first) and notifications within a cluster SHALL remain newest-first.

#### Scenario: Notifications from the same tab form one cluster
- **WHEN** a worktree has three notifications from tab A and one from tab B
- **THEN** the worktree section contains two clusters, and the tab-A cluster holds its three notifications newest-first

#### Scenario: Notification without a tab groups by surface
- **WHEN** two notifications share a `surfaceID` and have no `tabID`
- **THEN** they form a single cluster keyed by that surface

### Requirement: Collapsed rendering with inline expansion
A cluster with more than one notification SHALL render collapsed by default, showing only its newest notification plus an expand control labeled with the hidden count. Activating the control SHALL reveal the cluster's remaining notifications inline; activating it again SHALL collapse them. A cluster with exactly one notification SHALL render as a plain row with no expand control.

#### Scenario: Multi-notification cluster starts collapsed
- **WHEN** a session has 4 notifications and the inspector opens
- **THEN** only the newest notification is visible with a control indicating 3 older notifications

#### Scenario: Expanding and collapsing a cluster
- **WHEN** the user activates the expand control and then activates it again
- **THEN** the 3 older notifications appear inline, then hide again

#### Scenario: Single-notification session
- **WHEN** a session has exactly 1 notification
- **THEN** the row renders without any expand control

### Requirement: Hidden unread notifications stay discoverable
When a collapsed cluster hides at least one unread notification, the expand control SHALL indicate the hidden unread state. Collapsing SHALL NOT alter any notification's read state, and unread counting (toolbar bell badge, sidebar indicators) SHALL be unaffected by collapse state.

#### Scenario: Collapsed cluster with hidden unread
- **WHEN** a cluster is collapsed and 2 of its hidden notifications are unread
- **THEN** the expand control shows an unread hint for the hidden notifications

#### Scenario: Unread counts ignore collapse state
- **WHEN** 5 unread notifications exist across collapsed clusters
- **THEN** the toolbar bell badge still reports 5

### Requirement: Presentation-only behavior
Session collapse SHALL NOT delete, reorder, or mutate stored notifications. Dismiss-all and per-notification interactions SHALL keep their existing semantics regardless of collapse state.

#### Scenario: Data survives collapse
- **WHEN** a cluster is collapsed
- **THEN** `WorktreeTerminalState.notifications` still contains every notification unchanged
