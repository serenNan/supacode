## 1. Diff model and parser (TDD)

- [x] 1.1 RED: parser tests — multi-hunk text diff (kinds + old/new line numbers from `@@` headers), binary marker, empty diff, rename header pass-through
- [x] 1.2 GREEN: `GitFileDiff` / `GitDiffHunk` / `GitDiffLine` models + pure `parseFileDiff` alongside the existing parsers in `GitCommitHistory.swift`

## 2. Git client operations (TDD)

- [x] 2.1 RED: tests for `uncommittedFileDiff(at:path:)` (`git diff HEAD -- <path>`) and `commitFileDiff(at:hash:path:)` (`git show --format= --patch <hash> -- <path>`, incl. root commit) against fixture repos
- [x] 2.2 GREEN: add both operations to `GitClient` and wire through `GitClientDependency.make(shell:)` (SSH support falls out)

## 3. Reducer state and actions (TDD)

- [x] 3.1 RED: TestStore tests — `fileTapped` (uncommitted + commit sources) presents and loads; `fileDiffLoaded`/`fileDiffFailed` guarded by worktreeID + presented file; `diffDismissed` clears and cancels; reconciliation (selection change / pane hide) auto-dismisses
- [x] 3.2 GREEN: `PresentedDiff` state, new actions, `CancelID.fileDiff`, load effect via host-aware client in `RepositoriesFeature+GitHistory.swift`

## 4. Views

- [x] 4.1 Make `GitFileChangeList` rows buttons sending `fileTapped` (both uncommitted node and commit detail)
- [x] 4.2 Diff sheet view: header (file path, Close, Open in Editor when local), scrollable hunk/line rows with green/red styling, line-number gutters, binary placeholder, loading/error states, 4 000-line cap with truncation notice
- [x] 4.3 Present sheet from the worktree detail view bound to `gitHistory.presentedDiff`, Esc dismisses; Open in Editor performs the existing open-action mechanism with the file URL

## 5. Verification

- [x] 5.1 Full test suite green in the worktree (direct tuist/xcodebuild, not make)
- [x] 5.2 Build app, merge to main when user confirms, install and manual visual check (user)
