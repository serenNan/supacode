# Todo Panel — Tasks

Every task follows red → green → refactor (Superpowers TDD): write the failing test named in the task first, then the minimal implementation, then clean up.

## 1. Checklist parser

- [x] 1.1 Add `TodoChecklist` caseless enum with `parse(_:) -> [Section]` — tests first for: heading grouping, `-`/`*`/`+` bullets, indentation, checked (`[x]`/`[X]`) and non-checklist lines excluded from display output, line indices recorded, empty headings dropped
- [x] 1.2 Add `TodoChecklist.toggling(line:) -> String?` — tests for flipping `[ ]` ↔ `[x]` with surrounding bytes preserved and `nil` on non-task lines

## 2. File client and watcher

- [x] 2.1 Define `TodoFileClient` (`Clients/TodoFile/`): `read`, `write(verifyingLine:)`, `watch(paths:) -> AsyncStream<Event>`; B-mode `DependencyKey` (liveValue placeholder, testValue) + `DependencyValues` accessor
- [x] 2.2 Implement conflict-checked write: re-read, verify captured raw line at index, splice, write; test for the mismatch-aborts case (byte-identical remainder asserted)
- [x] 2.3 Implement `@MainActor TodoFileWatcherManager` (`Features/TodoPanel/BusinessLogic/`) copying the `WorktreeInfoWatcherManager` recipe: kqueue DispatchSource, injected-clock 200ms debounce, restart on `.rename`/`.delete`, parent-directory watch on both candidate locations for file creation; TestClock-driven tests for debounce coalescing, rename survival, and file-appears events
- [x] 2.4 Bind the manager to `TodoFileClient` in `makeStore(... withDependencies:)` in `supacodeApp.swift`

## 3. TodoPanelFeature reducer

- [x] 3.1 Create `Features/TodoPanel/Reducer/TodoPanelFeature.swift` with `@ObservableState`: resolve the active session's file (worktree root → primary checkout fallback, remote/none → empty state), load and parse on appear, expose the displayed file's source label — TestStore tests per spec scenario
- [x] 3.2 Follow selection: observe the selected worktree from `RepositoriesFeature`, re-resolve and reload when it changes (debounced, last selection wins) — tests for repo switch, worktree switch, no-selection
- [x] 3.3 Mark-done action: optimistic removal from panel + client write (`[ ]` → `[x]`); on conflict error, re-read and re-parse instead of applying — test both paths
- [x] 3.3b Send-to-agent action: clicking a task emits an insert request with the trimmed task text; root reducer routes it to `WorktreeTerminalState.focusAndInsertText(_:)` (no trailing `\r`); no-focused-surface → notice — tests for text content and no-op path
- [x] 3.4 Watcher lifecycle: start watching on panel `.task`, re-target watchers on selection change (including switch-to-worktree-file-when-it-appears), tear down on close — TestClock tests including external-edit refresh and teardown
- [x] 3.5 Compose `TodoPanelFeature` into the root reducer

## 4. Window and views

- [x] 4.1 Add `WindowID.todoPanel`; declare the `Window(id:)` scene in `supacodeApp.swift` modeled on the CLI Reference window (`.restorationBehavior(.disabled)`, default size)
- [x] 4.2 Build `Views/TodoPanelView.swift`: project title + source-file label, heading groups, rows with a done button and the task text as a send-to-agent button, empty states (no selection / no file / all done / remote); Dynamic Type, system colors, tooltips per UX standards
- [x] 4.3 Menu command (Window menu) via `FocusedAction` + open-bridge modifier calling `openWindow(id:)`, with keyboard shortcut; verify single-instance focus-on-reopen behavior

## 5. Verification and wrap-up

- [x] 5.1 Run the full test suite and `make build-app`; fix fallout
- [x] 5.2 Manual pass of every spec scenario (open panel, switch sessions across repos/worktrees, click task → text lands unsubmitted in the agent input, mark done → disappears + file updated, external edit via `echo >>`, atomic-save editor edit, worktree TODO.md appears while fallback shown, write conflict)
- [x] 5.3 Update CHANGELOG if the repo convention expects it; `openspec validate` clean

## 6. Sidebar bottom entry point

- [x] 6.1 Reference-count panel presentations in `TodoPanelFeature` (popover + window can overlap): watchers tear down only when the last presentation closes — TestStore tests first
- [x] 6.2 Add a persistent bottom-left Todos bar under the sidebar (above the onboarding card slot) with a tooltip'd button toggling an anchored popover hosting `TodoPanelView`
- [x] 6.3 Build, lint, full test suite; hold off installing until the user says so
