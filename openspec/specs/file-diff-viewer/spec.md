# file-diff-viewer Specification

## Purpose
TBD - created by archiving change add-file-diff-viewer. Update Purpose after archive.
## Requirements
### Requirement: Fetch a single file's diff
The system SHALL fetch a unified diff for one file: for an uncommitted file via `git diff HEAD -- <path>`, and for a file in a commit via `git show --format= --patch <hash> -- <path>`, executed through the worktree's host-aware git client (local or SSH).

#### Scenario: Uncommitted file diff
- **WHEN** the diff for an uncommitted file is requested
- **THEN** the system runs `git diff HEAD -- <path>` in the worktree and returns the unified diff output

#### Scenario: Commit file diff
- **WHEN** the diff for a file in a commit is requested
- **THEN** the system runs `git show --format= --patch <hash> -- <path>` and returns the unified diff output, including for a root commit

### Requirement: Parse unified diff into a structured model
The system SHALL parse unified diff text into hunks and lines, where each line carries a kind (context, added, removed), its text, and old/new line numbers derived from the `@@ -a,b +c,d @@` hunk headers. Binary-file diffs SHALL be represented with a binary flag instead of hunks.

#### Scenario: Text diff parsed into hunks
- **WHEN** unified diff text with one or more `@@` hunks is parsed
- **THEN** each hunk exposes its header and ordered lines with correct kinds and old/new line numbers

#### Scenario: Binary file
- **WHEN** the diff output contains a `Binary files … differ` marker
- **THEN** the parsed result is flagged binary and contains no hunks

#### Scenario: Empty diff
- **WHEN** the diff output is empty (file unchanged relative to the requested base)
- **THEN** the parsed result contains no hunks and is not flagged binary

### Requirement: File rows open a diff sheet
File rows in the History pane (expanded Uncommitted Changes node and expanded commit detail) SHALL be activatable; activating one presents a read-only diff sheet over the worktree detail area and loads that file's diff. Only one diff SHALL be presented at a time.

#### Scenario: Open uncommitted file diff
- **WHEN** the user activates a file row under Uncommitted Changes
- **THEN** a sheet opens showing a loading state, then the file's diff against HEAD

#### Scenario: Open commit file diff
- **WHEN** the user activates a file row inside an expanded commit's detail
- **THEN** a sheet opens showing that file's diff for that commit

#### Scenario: Load failure
- **WHEN** the diff command fails
- **THEN** the sheet shows the error message instead of a diff

#### Scenario: Stale response ignored
- **WHEN** a diff response arrives for a worktree or file that is no longer the presented one
- **THEN** the response is discarded

### Requirement: Diff sheet rendering
The diff sheet SHALL render the diff with monospaced text, added lines highlighted green, removed lines highlighted red, hunk headers visually distinct, and old/new line-number gutters. Binary files SHALL show a "binary file" placeholder. Rendering SHALL be capped at a fixed line budget with a truncation notice when exceeded.

#### Scenario: Added and removed line styling
- **WHEN** a diff containing added and removed lines is displayed
- **THEN** added lines render with green styling and removed lines with red styling, each with its line number

#### Scenario: Oversized diff truncated
- **WHEN** a diff exceeds the rendering line cap
- **THEN** only the first lines up to the cap render, followed by a notice that the diff was truncated

### Requirement: Dismissal
The diff sheet SHALL be dismissible via a Close control and the Escape key, and SHALL dismiss automatically when the History pane's context resets (selection change or pane hidden).

#### Scenario: Close control
- **WHEN** the user activates Close or presses Escape
- **THEN** the sheet dismisses and any in-flight diff load is cancelled

#### Scenario: Selection changes while presented
- **WHEN** the selected worktree changes or the History pane hides while a diff sheet is presented
- **THEN** the sheet dismisses

### Requirement: Open in Editor
The diff sheet SHALL offer an "Open in Editor" action for local worktrees that opens the diffed file in the user's configured editor via the existing open-action mechanism. The action SHALL NOT be offered for SSH worktrees.

#### Scenario: Open local file
- **WHEN** the user activates Open in Editor on a local worktree's diff sheet
- **THEN** the file opens in the configured editor

#### Scenario: Remote worktree
- **WHEN** the diff sheet is presented for an SSH worktree
- **THEN** the Open in Editor action is not shown

