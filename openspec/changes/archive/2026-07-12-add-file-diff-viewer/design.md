## Context

The History pane (`RepositoriesFeature+GitHistory.swift` + `WorktreeGitHistoryInspectorView.swift`) already lists changed files via `GitFileChangeList`, fed by `git diff HEAD --numstat` / `git show <hash> --numstat`. Numbers only — no line-level content. The inspector pane is 280–480pt wide, too narrow for a diff, so presentation must happen over the detail area.

`WorkspaceClient.perform(...)` + `OpenWorktreeAction` already implement "open a target URL in the user's chosen app" (used for the worktree-level VS Code open action); targets resolve to arbitrary URLs, so opening a single file reuses it unchanged.

## Goals / Non-Goals

**Goals:**
- Click any file row in the History pane → see its unified diff without leaving Supacode.
- Works for uncommitted changes and for any listed commit.
- Escape hatch: Open in Editor button on the diff sheet (local worktrees).

**Non-Goals:**
- Editing, staging, discarding, or any mutation.
- Side-by-side diff layout, syntax highlighting inside diff lines, word-level diff (all possible later; first version is unified + whole-line coloring).
- Diffs for untracked files (`git diff HEAD` doesn't include them, consistent with the existing numstat list).

## Decisions

1. **Presentation: `.sheet` over the worktree detail area, not inside the inspector.**
   The pane is too narrow. A sheet is standard macOS, dismisses with Esc for free, and needs no new window plumbing. Alternative — a new window per diff — adds window-management complexity with no benefit for a read-only glance.

2. **Diff commands, one file per invocation:**
   - Uncommitted: `git diff HEAD -- <path>`
   - Commit: `git show --format= --patch <hash> -- <path>` (empty `--format=` drops the commit header; works for root commits, where `<hash>^` doesn't exist).
   Fetching per-file on demand keeps payloads small and reuses the existing `GitOperation` plumbing; renames surface as the pre-image/post-image paths git prints, which the parser passes through.

3. **Parse into a structured model, don't render raw text.**
   `GitFileDiff { hunks: [GitDiffHunk { header, lines: [GitDiffLine { kind: context/added/removed, text, oldNumber?, newNumber? }] }], isBinary }`. A pure parser (`parseFileDiff`) beside the existing `parseCommitLog`/`parseNumstat` in `GitCommitHistory.swift`, unit-testable without git. Line numbers computed while parsing hunk headers (`@@ -a,b +c,d @@`). Binary detection: `Binary files ... differ` line → `isBinary`.

4. **State lives in `GitHistoryState`, following the pane's existing patterns.**
   New fields: `presentedDiff: PresentedDiff?` where `PresentedDiff { source: uncommitted | commit(hash:), filePath, diff: GitFileDiff?, error: String? }`. Actions: `fileTapped(source:path:)`, `fileDiffLoaded(worktreeID:...)`, `fileDiffFailed(...)`, `diffDismissed`. Same worktreeID-guard + `CancelID` (new `case fileDiff`) + cancel-on-reconciliation as the other loads. The default-arm reconciliation already clears `gitHistory` wholesale, so the sheet auto-dismisses on selection change/pane hide with no extra code.

5. **View: plain `ScrollView` + `LazyVStack` of line rows.**
   Monospaced font, `.green`/`.red` foreground with low-opacity background tint for added/removed, secondary hunk headers, both line-number gutters. No `NSTextView`/attributed-string machinery — diffs of one file at a time are small enough for SwiftUI rows, and 200-commit histories already proved `Form`/`ForEach` fine at this scale. Cap displayed lines (e.g. 4 000) with a truncation footer to keep pathological diffs safe.

6. **Open in Editor: reuse `WorkspaceClient.perform` with the file URL as target; hidden for SSH worktrees** (the file doesn't exist locally). Viewing still works remotely because the diff text comes over the same host-aware git client.

## Risks / Trade-offs

- [Huge single-file diffs (lockfiles, generated code) could stall rendering] → hard cap on rendered lines + "Showing first N lines" footer; parser itself is O(n) on text.
- [Rename/copy diffs have two paths] → parser keeps git's headers verbatim in the hunk header area; row still opens the post-image path in the editor.
- [File deleted on disk but user hits Open in Editor] → editors handle a missing path gracefully (or no-op); button stays enabled for simplicity, error surfaced via existing open-action error path.
- [`git show <hash> -- <path>` on a merge commit shows no diff for unconflicted files] → acceptable: history list is `--first-parent` and file lists for merges come from the same `git show`, so the file list and diff stay consistent.

## Open Questions

None blocking.
