# Todo Panel — Design

## Context

Supacode already has: auxiliary read-only windows declared as `Window(id:)` scenes in `supacodeApp.swift` (CLI Reference, Deeplink Reference), a repository list with local disk roots in `RepositoriesFeature.State.repositories` (`Repository.localRootURL`), and a proven kqueue file-watching pattern (`WorktreeInfoWatcherManager`: `DispatchSource` + 200ms debounce + restart-on-rename). There is no markdown parsing dependency in the project. The Todo panel composes these existing pieces; the only genuinely new code is a small checklist parser and a per-file watcher manager.

## Goals / Non-Goals

**Goals:**
- Standalone single-instance window showing the active session's **unchecked** `TODO.md` items, following sidebar selection
- One-click hand-off: clicking a task inserts its text into the active session's agent input
- Byte-preserving done-marking write-back, safe under concurrent external edits
- Live refresh driven by filesystem events, active only while the window is open
- Upstreamable: generic markdown checklists, no third-party-app coupling

**Non-Goals:**
- Editing task text, adding/removing/reordering items (view + toggle only, v1)
- Rendering non-checklist markdown (prose, tables, code blocks)
- Remote (SSH) repositories — skipped in v1 (`localRootURL == nil`)
- Configurable file names/paths beyond `TODO.md` at the primary worktree root

## Decisions

### D1: Standalone `Window(id:)` scene, opened via bridge modifier
New `WindowID.todoPanel` constant; a `Window("Todos", id: WindowID.todoPanel)` scene in `supacodeApp.swift` body modeled on the CLI Reference window (`.restorationBehavior(.disabled)`, sensible `.defaultSize`). A menu command under **Window** publishes a `FocusedAction`-wrapped action (per `FocusedAction` conventions in `App/Models/FocusedAction.swift`); opening goes through a bridge view modifier that calls `@Environment(\.openWindow)` — same pattern as `SettingsOpenBridge`. `Window` (vs `WindowGroup`) gives single-instance + focus-on-reopen for free.

*Alternative considered:* inspector pane like the Git History pane — rejected because the user-facing requirement is a window that survives independent of the selected worktree.

### D2: `TodoPanelFeature` as an app-level child feature, driven by selection
`Features/TodoPanel/` with the standard layout (`Reducer/TodoPanelFeature.swift`, `Views/`, `BusinessLogic/`). It is composed into the root reducer; the panel window scopes into it from the shared root store. It observes `RepositoriesFeature`'s selected worktree (`selectedWorktreeID` / `worktree(for:)`) read-only and re-resolves its displayed file whenever the selection changes. Remote sessions (`localRootURL == nil`) show the empty state.

### D2b: File resolution — worktree first, primary checkout fallback
For the active session the candidate paths are, in priority order: `<worktree root>/TODO.md`, then `<repository primary checkout root>/TODO.md` (`Repository.localRootURL`). The first existing file wins and the panel labels the source (worktree vs repository). Both candidate locations stay watched so a higher-priority file appearing switches the panel to it. No file is created implicitly.

### D3: Hand-rolled line-based checklist parser
A caseless `enum TodoChecklist` (no top-level free functions, per project guidelines) with pure static functions:
- `parse(_ text: String) -> [Section]` — walks lines; a task item matches optional indentation, bullet `-`/`*`/`+`, then `[ ]`/`[x]`/`[X]`; groups under the nearest preceding heading (`#`+). Each item records its **line index** and raw line.
- `toggling(line: String) -> String?` — flips just the checkbox marker inside one line, returning `nil` when the line is not a task item.

*Alternative considered:* `apple/swift-markdown` — rejected: write-back requires operating on raw lines to guarantee byte preservation, so a full AST adds a dependency without removing any of the line-level bookkeeping. The grammar we honor is ~2 regex-free string scans.

### D4: Toggle write-back = read, verify, splice one line, atomic write
Toggling sends the item's line index and the raw line captured at parse time. The client re-reads the file, verifies `lines[index]` still equals the captured raw line; on match it splices the toggled line and writes the joined text back; on mismatch it throws a conflict error and the reducer re-parses the fresh content instead of applying the toggle (spec: no silent misapplied writes). Files are written with the original content's line endings.

### D5: File watching via a B-mode dependency client + `@MainActor` manager
`TodoFileClient` (in `Clients/TodoFile/`) exposes `read`, `write`, and `watch(paths:) -> AsyncStream<Event>`. Its `liveValue` is a `fatalError` placeholder bound in `makeStore(... withDependencies:)` to a new `@MainActor TodoFileWatcherManager` — the same B-mode convention as `WorktreeInfoWatcherClient`. The manager copies the `WorktreeInfoWatcherManager` recipe: `open(path, O_EVTONLY)` + `DispatchSource.makeFileSystemObjectSource(eventMask: [.write, .rename, .delete, .attrib])`, injected-clock 200ms debounce, and **watcher restart on `.rename`/`.delete`** (atomic saves from editors — and our own write-back — surface as renames). The manager watches both candidate locations' parent directories so a `TODO.md` appearing (including a higher-priority worktree file) is detected. Watchers start on the panel's `.task`/appear action, re-target when the selection changes, and are torn down on window close.

### D6: Send-to-agent via the existing terminal insertion path
Each row has two hit targets: a done button (checkbox) and the task text as a button. Clicking the text routes an action to the root reducer, which reuses the existing terminal insertion mechanism — `WorktreeTerminalState.focusAndInsertText(_:)` (`Features/Terminal/Models/WorktreeTerminalState.swift:682`), already exercised by `WorktreeTerminalManager` — to focus the active session's surface and insert the task text **without** a trailing `\r` (the user reviews and submits). Inserted text = the item's content after the checkbox marker, trimmed. No focused surface → the reducer reports a no-op notice back to the panel. Rationale: reusing the proven insertion path avoids new surface plumbing and keeps the panel feature surface-agnostic.

### D7: Testing
`supacodeTests/TodoPanelFeatureTests.swift` (+ parser tests): `TestStore` with `TodoFileClient.testValue` overridden per test; debounce/refresh driven by `TestClock` (`clock.advance`), never `Task.sleep` — mirroring `WorktreeInfoWatcherManagerTests`. Scenarios from the spec map 1:1 to tests: grouping, checked/non-checklist lines hidden, byte-identical done-marking, conflict abort, send-to-agent (insert action emitted with the right text; no-surface notice), external-edit refresh, file-appears refresh, teardown on close.

## Risks / Trade-offs

- [Own write-back triggers our watcher → redundant re-read] → acceptable: re-read is cheap and debounced; content converges. No suppression bookkeeping in v1.
- [Editors that rewrite whole files (atomic rename) kill kqueue fds] → handled by the restart-on-rename branch copied from `WorktreeInfoWatcherManager`; covered by a test.
- [Large TODO.md files] → parsing is O(lines) per change and files are human-authored; no pagination in v1.
- [Rapid session switching churns watchers] → load/watch effects are cancel-in-flight (TCA cancellable); the last selection wins without added latency.
- [Selected worktree removed while panel open] → panel falls back to the empty state until a new selection arrives.
- [Upstream may prefer a different surface (inspector vs window)] → feature logic (parser, client, reducer) is surface-agnostic; only the scene declaration would change in review.

## Open Questions

- None blocking.

### D8: Sidebar bottom entry point (added after first manual pass)
The menu-only entry proved undiscoverable. A persistent bottom-left bar under the sidebar (stacked above the mutually-exclusive onboarding card slot in `ContentView`'s bottom `safeAreaInset`) hosts a Todos button that toggles a popover embedding the same `TodoPanelView`. Because the popover and the standalone window can be open at once and both drive `panelAppeared`/`panelClosed`, the reducer reference-counts open presentations and only stops watchers when the count reaches zero.
