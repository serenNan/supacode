## Why

When a Claude session dies mid-response with an API error (e.g. `API Error: Connection closed mid-response`), Claude Code emits a **normal `Stop` hook**, not a failure — so Supacode's sidebar shows the session as plain "idle", indistinguishable from a completed turn. The user has no way to know a session silently broke and needs a manual restart. Compaction (`PreCompact`) is likewise invisible on the tab, even though it is a native hook event that other tools (clawd-on-desk) already surface.

## What Changes

- **API-error detection in the Claude `Stop` hook**: the installed `Stop` hook command reads the Claude Code hook JSON on stdin, extracts `transcript_path`, scans the transcript tail for a **current-turn** `isApiErrorMessage:true` entry, and — when found — emits a new `event=api_error` OSC 3008 signal instead of the normal `event=idle`. Detection is structural (transcript flag), not terminal-text scraping.
- **New presence event `api_error`** flowing through the existing hook → OSC 3008 → `AgentPresenceFeature` → sidebar fan-out pipeline.
- **New presence event `compacting`** mapped from the native Claude Code `PreCompact` hook (Supacode currently maps no compaction event). `PostCompact` is intentionally not mapped (compaction finishing is not turn completion).
- **Sidebar indicator**: an errored session shows a distinct red `exclamationmark.triangle` badge with a "needs manual restart" tooltip and floats to the top of the Active rail (highest-priority classification bucket). A compacting session shows a subtle transient "compacting" indicator (no priority float, no error styling).
- **Clear semantics**: the error flag clears on the surface's next `busy` / `session_start` event (agent restarted) or when the user focuses the tab.
- **Menu-bar notification**: an API error also raises an entry in the existing menu-bar notification status item so the user is alerted when the app is unfocused.

Error *type* (rate_limit / server_error / …) is intentionally **not** surfaced in the UI — a single "needs restart" red badge is enough.

## Capabilities

### New Capabilities
- `agent-error-presence`: hook-derived detection of Claude API errors (via transcript `isApiErrorMessage`) and compaction state (via `PreCompact`), their propagation through the presence pipeline as new events, and their surfacing on the sidebar tab (red error badge + priority float, transient compacting indicator) and menu-bar notification list.

### Modified Capabilities
<!-- No existing spec's requirements change; the terminal-file-links spec is unrelated. -->

## Impact

- **Hook generation (SupacodeSettingsShared)**: `ClaudeHookSettings.swift` (Stop hook command gains transcript inspection; new `PreCompact` mapping), `AgentPresenceOSC.swift` (new `HookEvent` actions `api_error`, `compacting`; pure-`awk` transcript tail scan for SSH portability — no `jq`/`python`).
- **Event model**: `AgentHookSocketServer.swift` `EventName` enum gains `apiError`, `compacting`.
- **Presence**: `AgentPresenceFeature.swift` `Activity` / state machine handles the new events (error is sticky until restart/focus; compacting is transient).
- **Sidebar state & render**: `SidebarItemFeature.swift` (new `agentError` leaf state + clear logic), `SidebarStructure.swift` (`SidebarActiveClassification` top-priority bucket), `SidebarItemView.swift` (red badge + tooltip; compacting indicator).
- **Fan-out**: `AppFeature.swift` routes the new events per-surface; `TerminalClient.swift` / `WorktreeTerminalState.swift` carry them.
- **Menu bar**: `MenuBarNotificationList.swift` gains an error entry path.
- **Tests**: `AgentHookCommandTests.swift` (Stop command emits transcript-gated `api_error`; `PreCompact` maps to `compacting`), presence reducer tests (set/clear transitions), classification tests (error floats to top), and a pure-function transcript-scan test.
- **External dependency**: relies on Claude Code's `isApiErrorMessage` transcript format (observed CC 2.1.150) — same dependency clawd-on-desk accepts.
