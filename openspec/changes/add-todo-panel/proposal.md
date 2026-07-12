# Todo Panel

## Why

Supacode users coordinate multiple agents across repositories, but the plain-markdown task lists that live in those repositories (`TODO.md`) are invisible inside the app — checking what's left to do means leaving Supacode or `cat`-ing the file in a terminal. A lightweight panel that surfaces each repository's checklist keeps planning context next to the agents doing the work.

## What Changes

- Add a **Todo panel**: a standalone auxiliary window showing the markdown checklist of the **active session's project**, switching content as the sidebar selection moves between sessions/worktrees/repositories.
- File resolution per session: `TODO.md` at the session's worktree root, falling back to the repository's primary checkout root; the panel labels which file is shown.
- Parse GitHub-flavored markdown task lists (`- [ ]` / `- [x]`), preserving section headings as groups; only unchecked items are shown — checked items and non-checklist content are hidden but preserved on write-back.
- Marking an item done rewrites only that checkbox marker in the file (all other bytes untouched) and removes it from the panel.
- Clicking an item's text focuses the active session's terminal and inserts the task text into the agent's input (not submitted), for one-click hand-off to the agent.
- Watch the displayed `TODO.md` (and candidate locations) for external changes (agent edits, editor saves, git checkout) and refresh the panel automatically.
- When no `TODO.md` exists at either location, show an empty state; no file is ever created implicitly.
- Panel is generic over plain markdown checklists — no third-party app integration or custom file format.

## Capabilities

### New Capabilities

- `todo-panel`: Displaying, grouping, toggling, and live-refreshing the active session's `TODO.md` checklist in a dedicated selection-following window.

### Modified Capabilities

<!-- none — this is additive; no existing spec'd behavior changes -->

## Impact

- **New TCA feature** (`TodoPanelFeature`): state, reducer, view, plus a new window scene registered in the app entry point and a menu/command to open it.
- **RepositoriesFeature**: read-only consumption of the repository list and root paths to locate `TODO.md` files (no state changes expected).
- **New dependency client** for checklist file IO + watching (following existing swift-dependencies client conventions); file watching reuses the codebase's existing watcher mechanism if one exists.
- **Tests**: reducer tests for parsing, toggling, write-back, and refresh-on-change (TestClock-driven).
- No new third-party dependencies anticipated; parsing is line-based and small enough to hand-roll.
