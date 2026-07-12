## Why

The History inspector pane (change `add-git-history-pane`, merged) lists changed files with +/- line counts, but seeing *what* changed still requires opening VS Code or running `git diff` in the terminal. A read-only per-file diff view closes that gap — the user can review uncommitted work and past commits entirely inside Supacode.

Editing is explicitly out of scope: Supacode is a terminal for orchestrating coding agents, not an editor. For the rare "I want to change this line myself" case the diff view offers an Open in Editor escape hatch.

## What Changes

- File rows in the History pane (both the expanded Uncommitted Changes node and expanded commit details) become clickable.
- Clicking a file presents a read-only diff of that file as a sheet over the detail area: unified diff with green added / red removed line highlighting, monospaced, hunk headers, line numbers.
- The sheet has an "Open in Editor" button that opens the file in the user's configured editor (same mechanism as the existing worktree open action), plus a Close button / Esc to dismiss.
- Diff sources: uncommitted file → `git diff HEAD -- <path>`; commit file → `git show <hash> -- <path>`. Binary files show a "Binary file" placeholder instead of a diff.
- Remote (SSH) worktrees work for viewing via the same host-aware git client; Open in Editor is disabled for them.

## Capabilities

### New Capabilities
- `file-diff-viewer`: Read-only per-file diff presentation — loading a unified diff for an uncommitted or committed file, parsing it into hunks/lines, rendering with add/remove highlighting, and the Open in Editor action.

### Modified Capabilities

<!-- git-history-pane spec is still in its unarchived change, not yet in openspec/specs/; the clickable-file behavior is captured in the new capability's requirements instead. -->

## Impact

- `supacode/Clients/Git/GitCommitHistory.swift` (or new file): diff model + unified-diff parser.
- `supacode/Clients/Git/GitClient.swift` + `supacode/Clients/Repositories/GitClientDependency.swift`: two new operations (uncommitted file diff, commit file diff).
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+GitHistory.swift`: state/actions for selected file, loaded diff, load failure, dismissal.
- `supacode/Features/Repositories/Views/WorktreeGitHistoryInspectorView.swift`: file rows become buttons.
- New view file for the diff sheet; sheet presentation hooked into the worktree detail view.
- Tests: parser unit tests + reducer TestStore tests.
- No new dependencies; no breaking changes.
