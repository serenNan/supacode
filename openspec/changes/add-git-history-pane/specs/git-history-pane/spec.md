## ADDED Requirements

### Requirement: History inspector pane
The system SHALL provide a third inspector pane "History" alongside the existing Git/PR and Notifications panes, showing the commit history of the currently selected worktree. The pane SHALL be toggleable via a trailing toolbar button, a View menu command, and a keyboard shortcut, following the same pattern as the existing panes.

#### Scenario: Open history pane from toolbar
- **WHEN** the user clicks the History toolbar toggle while a git worktree is selected
- **THEN** the inspector opens showing the commit history pane for that worktree

#### Scenario: Toggle closes the pane
- **WHEN** the History pane is visible and the user activates the toggle (toolbar, menu, or shortcut) again
- **THEN** the inspector closes

#### Scenario: Folder repository selected
- **WHEN** the History pane is opened while a non-git folder is selected
- **THEN** the pane shows a "Not a Git Repository" unavailable state and performs no git calls

### Requirement: Linear commit list with decorations
The pane SHALL list the selected worktree's commits in first-parent order (most recent first, capped at 200), each row showing a graph dot with connecting line, the commit subject, author, and relative time. Rows whose commit carries ref decorations SHALL display badges for each ref (e.g. `main`, `origin/main`), with the HEAD branch visually distinguished.

#### Scenario: Commit rows render
- **WHEN** history loads for a worktree with commits
- **THEN** each row shows graph dot, subject, author, relative time, in first-parent order

#### Scenario: Branch badges
- **WHEN** a listed commit is pointed to by local or remote refs
- **THEN** the row shows one badge per ref, and the HEAD branch badge is visually distinct

#### Scenario: History capped
- **WHEN** the worktree has more than 200 first-parent commits
- **THEN** only the most recent 200 are listed and a footer indicates the list is truncated

### Requirement: Outgoing and uncommitted change indicators
The pane SHALL group commits that are ahead of the configured upstream under an "Outgoing" section header, and SHALL show an "Uncommitted Changes" node above the list whenever the selected worktree has uncommitted changes (non-zero diff line counts).

#### Scenario: Outgoing commits grouped
- **WHEN** the worktree's HEAD is N commits ahead of its upstream
- **THEN** the first N commits appear under an "Outgoing" section header

#### Scenario: No upstream configured
- **WHEN** the current branch has no upstream (or HEAD is detached)
- **THEN** no "Outgoing" section is shown and the list renders normally

#### Scenario: Uncommitted changes node
- **WHEN** the selected worktree has uncommitted changes
- **THEN** an "Uncommitted Changes" node with a hollow dot appears at the top of the list

### Requirement: Expandable commit detail
The system SHALL expand a commit row in place when clicked, lazily loading and showing the full commit message, author, absolute date, hash, and the list of changed files with per-file added/removed line counts. Clicking another row SHALL collapse the previous one. A context menu SHALL offer copying the commit hash and the commit message.

#### Scenario: Expand detail on click
- **WHEN** the user clicks a commit row
- **THEN** the row expands showing full message, author, absolute date, hash, and changed files with +/- counts, loaded on demand

#### Scenario: Only one row expanded
- **WHEN** a row is expanded and the user clicks a different row
- **THEN** the previous row collapses and the newly clicked row expands

#### Scenario: Copy from context menu
- **WHEN** the user right-clicks a commit row and chooses Copy Hash
- **THEN** the full commit hash is placed on the pasteboard

### Requirement: History freshness
The system SHALL load history only while the History pane is visible, and SHALL refresh it when the selected worktree changes or when the selected worktree's branch or files change (via the existing worktree info watcher). In-flight queries SHALL be cancelled when the selection changes. A manual refresh button SHALL be available in the pane header.

#### Scenario: No git calls while hidden
- **WHEN** the History pane is closed or another pane is active
- **THEN** worktree events trigger no history git queries

#### Scenario: Refresh on selection change
- **WHEN** the History pane is visible and the user selects a different worktree
- **THEN** any in-flight query is cancelled and history reloads for the new selection

#### Scenario: Refresh on commit
- **WHEN** the History pane is visible and the watcher reports a branch or file change for the selected worktree
- **THEN** the history reloads

#### Scenario: Load failure
- **WHEN** the history git query fails
- **THEN** the pane shows an error state with a Retry action instead of stale or empty content
