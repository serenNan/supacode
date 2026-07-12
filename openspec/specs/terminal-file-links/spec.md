# terminal-file-links Specification

## Purpose

Detects, resolves, and routes file references clicked inside a terminal surface: intercepting Ghostty's open-url action, resolving clicked text into a worktree-relative path and optional line number, and opening the result in the History diff viewer (with diff-sheet line targeting) instead of the system default handler. Non-matching links (other URL schemes, files outside the worktree, nonexistent files, remote/SSH worktrees) fall back to the existing system-open behavior. Media and binary files open with the system default application instead of the diff viewer.

## Requirements

### Requirement: Resolve clicked terminal text to a worktree file reference
The system SHALL resolve a clicked terminal link string into a worktree file reference consisting of a path relative to the worktree root and an optional line number. Resolution SHALL accept bare paths, `path:line`, `path:line:col`, and `file://` URIs; strings with any other URL scheme SHALL NOT resolve. Relative paths SHALL be resolved against the surface's reported pwd, falling back to the worktree root when no pwd is available. A reference SHALL only resolve when the file exists and lies inside the worktree root.

#### Scenario: Relative path with line number
- **WHEN** the clicked text is `supacode/Foo.swift:123`, the pwd is the worktree root, and that file exists in the worktree
- **THEN** resolution yields relative path `supacode/Foo.swift` and line `123`

#### Scenario: Path with line and column
- **WHEN** the clicked text is `src/main.swift:10:5` and `src/main.swift` exists in the worktree
- **THEN** resolution yields relative path `src/main.swift` and line `10`

#### Scenario: Exact filename containing a colon wins
- **WHEN** the clicked text is `notes.txt:12` and a file literally named `notes.txt:12` exists in the worktree
- **THEN** resolution yields relative path `notes.txt:12` with no line number

#### Scenario: file URI from an OSC 8 hyperlink
- **WHEN** the clicked link is a `file://` URI pointing at a file inside the worktree
- **THEN** resolution yields that file's worktree-relative path with no line number

#### Scenario: Non-file scheme does not resolve
- **WHEN** the clicked link has scheme `https`
- **THEN** resolution yields nothing

#### Scenario: File outside the worktree does not resolve
- **WHEN** the clicked text resolves to an existing file outside the worktree root (including a sibling directory whose name shares the root's prefix)
- **THEN** resolution yields nothing

#### Scenario: Nonexistent file does not resolve
- **WHEN** the clicked text names a path that does not exist after stripping any `:line` / `:line:col` suffix
- **THEN** resolution yields nothing

### Requirement: Intercept terminal link opens for worktree files
When a Ghostty open-url action fires on a local worktree's surface and the clicked link resolves to a worktree file reference, the system SHALL route the reference to the History diff viewer instead of opening it with the system handler. When the link does not resolve (other scheme, outside worktree, nonexistent file) or the worktree is remote, the system SHALL preserve the existing behavior of opening via `NSWorkspace`.

#### Scenario: Worktree file click routes internally
- **WHEN** the user Cmd+clicks `supacode/Foo.swift:123` in a local worktree's terminal and the file exists
- **THEN** no system open occurs and a file-reference event carrying the worktree id, relative path, and line is emitted

#### Scenario: Web URL keeps system behavior
- **WHEN** the user Cmd+clicks `https://example.com` in the terminal
- **THEN** the URL opens via the system handler as before

#### Scenario: Remote worktree keeps system behavior
- **WHEN** the user Cmd+clicks a path in a remote (SSH) worktree's terminal
- **THEN** the link opens via the existing system path with no internal routing

### Requirement: Media and binary files open with the system default application
When a resolved worktree file reference has a media or binary file extension (images, PDF, audio/video, archives, office documents), the system SHALL open the file's absolute path with the system default application instead of the diff viewer. Extension matching SHALL be case-insensitive.

#### Scenario: Image opens with the system default application
- **WHEN** the user Cmd+clicks `output/screenshot.png` in a local worktree's terminal and the file exists
- **THEN** the file opens with the system default application and no diff sheet is presented

#### Scenario: Uppercase extension
- **WHEN** the clicked reference resolves to a file ending in `.PNG`
- **THEN** it is treated the same as `.png` and opens with the system default application

#### Scenario: Source file still opens the diff viewer
- **WHEN** the clicked reference resolves to a `.swift` file
- **THEN** the diff viewer flow applies, not the system open

### Requirement: Open the referenced file in the History diff viewer
On receiving a terminal file-reference event for the currently selected worktree, the system SHALL present the History inspector pane and open the file's uncommitted diff in the diff sheet, carrying the optional target line. Events for a worktree other than the selected one SHALL be ignored.

#### Scenario: Click opens History pane and diff sheet
- **WHEN** a file-reference event for the selected worktree arrives while the History pane is closed
- **THEN** the inspector opens on the History pane and the diff sheet presents that file's uncommitted diff

#### Scenario: History pane already open
- **WHEN** a file-reference event arrives while the History pane is already visible
- **THEN** the diff sheet presents the referenced file's uncommitted diff without reloading the pane unnecessarily

#### Scenario: Event for unselected worktree ignored
- **WHEN** a file-reference event arrives whose worktree id differs from the selected worktree
- **THEN** no state changes occur

### Requirement: Diff sheet scrolls to the target line
When the diff sheet is opened with a target line, it SHALL scroll to the first diff line whose new-file line number is at or after the target once the diff loads. When no such line exists or the target lies beyond the rendering cap, the sheet SHALL show the diff unscrolled.

#### Scenario: Target line inside the diff
- **WHEN** the diff sheet opens with target line 123 and the loaded diff contains a line with new-file number ≥ 123
- **THEN** the sheet scrolls to that line

#### Scenario: Target line not present
- **WHEN** the diff sheet opens with a target line beyond every hunk in the loaded diff
- **THEN** the sheet displays the diff from the top without scrolling
