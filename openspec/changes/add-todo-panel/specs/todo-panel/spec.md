## ADDED Requirements

### Requirement: Todo panel window
The app SHALL provide a standalone Todo panel window, openable from the main menu with a keyboard shortcut. Only one instance SHALL exist at a time; invoking the command again SHALL bring the existing window to front.

#### Scenario: Opening the panel
- **WHEN** the user invokes the Todo panel menu command
- **THEN** a dedicated window opens showing the current session's project checklist

#### Scenario: Reopening while already open
- **WHEN** the Todo panel is already open and the user invokes the command again
- **THEN** the existing window is focused instead of a second window being created

### Requirement: Sidebar bottom entry point
The main window's sidebar SHALL show a persistent Todos button at its bottom-left. Clicking it SHALL toggle an anchored popover presenting the same checklist content as the Todos window. The button MUST have a tooltip naming the action and the keyboard shortcut.

#### Scenario: Opening the popover
- **WHEN** the user clicks the sidebar's bottom-left Todos button
- **THEN** a popover anchored to the button shows the active session's checklist

#### Scenario: Popover and window are independent presentations
- **WHEN** the checklist is visible in both the popover and the standalone window and the user closes one of them
- **THEN** the other keeps refreshing (file watchers stay active until the last presentation closes)

### Requirement: Panel follows the active session
The panel SHALL display the checklist for exactly one project: the repository owning the currently selected session (worktree/tab). When the selection moves to a session of a different worktree or repository, the panel SHALL switch its content accordingly.

#### Scenario: Switching sessions switches content
- **WHEN** the panel is open and the user selects a session belonging to a different repository
- **THEN** the panel replaces its content with that repository's checklist

#### Scenario: No session selected
- **WHEN** no session is selected
- **THEN** the panel shows an empty state prompting to select a session

### Requirement: Checklist file resolution
For the active session, the panel SHALL read `TODO.md` from the session's worktree root; if that file does not exist, it SHALL fall back to `TODO.md` at the repository's primary checkout root. If neither exists, the panel SHALL show an empty state and MUST NOT create any file implicitly.

#### Scenario: Worktree has its own TODO.md
- **WHEN** the active session's worktree root contains a `TODO.md`
- **THEN** the panel displays that file's unchecked items

#### Scenario: Fallback to primary checkout
- **WHEN** the active session's worktree root has no `TODO.md` but the repository's primary checkout root does
- **THEN** the panel displays the primary checkout's unchecked items

#### Scenario: Neither location has a TODO.md
- **WHEN** neither the worktree root nor the primary checkout root contains a `TODO.md`
- **THEN** the panel shows an empty state explaining no `TODO.md` was found, and no file is created

### Requirement: Markdown checklist parsing
The panel SHALL parse GitHub-flavored markdown task list lines (`- [ ]` unchecked, `- [x]`/`- [X]` checked, also accepting `*` or `+` bullets and leading indentation) and SHALL group items under the nearest preceding markdown heading. Only unchecked items SHALL be displayed; checked items and lines that are not task list items SHALL NOT be displayed but MUST be preserved verbatim when the file is rewritten. Headings whose items are all checked or absent SHALL be hidden.

#### Scenario: Parsing grouped checklist items
- **WHEN** the displayed `TODO.md` contains headings followed by `- [ ]` and `- [x]` lines
- **THEN** the panel shows only the unchecked items, grouped under their heading titles

#### Scenario: Completed items are hidden
- **WHEN** the displayed `TODO.md` contains `- [x]` lines
- **THEN** those items do not appear in the panel and remain untouched in the file

#### Scenario: Non-checklist content is ignored for display
- **WHEN** the displayed `TODO.md` contains prose, links, or code blocks between checklist items
- **THEN** those lines do not appear in the panel

### Requirement: Completing an item writes back to the file
Marking an item done in the panel SHALL rewrite only that line's checkbox marker (`[ ]` → `[x]`) in the displayed source file, preserving every other byte of the file, and SHALL remove the item from the panel.

#### Scenario: Completing an item
- **WHEN** the user marks an item done in the panel
- **THEN** the corresponding line in the displayed file changes from `- [ ]` to `- [x]`, the rest of the file is byte-identical, and the item disappears from the panel

#### Scenario: Write-back conflict with a changed file
- **WHEN** the file on disk changed after the panel last read it and the targeted line no longer matches
- **THEN** the write is aborted, the panel re-reads the file, and the user's toggle is not applied silently

### Requirement: Clicking an item sends it to the active session
Clicking an item's text SHALL focus the active session's terminal surface and insert the item's task text (without the checkbox marker) into it, WITHOUT submitting — the user reviews and presses Return themselves. If no terminal surface is focused for the active session, the panel SHALL indicate that nothing was sent.

#### Scenario: Sending a task to the agent
- **WHEN** the user clicks a task's text while an agent session is active
- **THEN** the session's terminal is focused and the task text appears in its input, not yet submitted

#### Scenario: No focused surface
- **WHEN** the user clicks a task's text but the active session has no focused terminal surface
- **THEN** no text is sent and the panel surfaces a brief notice

### Requirement: Live refresh on external changes
The panel SHALL watch the displayed file — and both candidate locations for appearance of a higher-priority file — and refresh automatically, coalescing bursts of change events. Watching SHALL only be active while the panel window is open.

#### Scenario: External edit refreshes the panel
- **WHEN** the panel is open and an agent or editor modifies the displayed `TODO.md`
- **THEN** the panel reflects the new contents without user action

#### Scenario: Worktree TODO.md appears while fallback is shown
- **WHEN** the panel is showing the primary checkout's file and a `TODO.md` is created at the active worktree's root
- **THEN** the panel switches to the worktree's file

#### Scenario: Panel closed stops watching
- **WHEN** the Todo panel window is closed
- **THEN** all file watchers started by the panel are torn down
