## ADDED Requirements

### Requirement: Claude Stop hook detects current-turn API errors from the transcript

The Claude Code `Stop` hook command installed by Supacode SHALL read the hook JSON on stdin, extract `transcript_path`, and scan the tail of that transcript for the most recent `isApiErrorMessage:true` entry belonging to the current turn. When such an entry exists, the hook SHALL emit an OSC 3008 presence signal with `event=api_error`; otherwise it SHALL emit the normal `event=idle`. Detection SHALL be structural (transcript flag) and SHALL NOT scan terminal scrollback. The scan SHALL use only portable shell tooling (`awk`), with no dependency on `jq` or `python`, so it works over SSH.

#### Scenario: Turn ends with a connection error
- **WHEN** a Claude turn ends and the transcript tail's most recent error-bearing entry is `isApiErrorMessage:true` with no later `user` or non-error `assistant` entry
- **THEN** the `Stop` hook emits an OSC 3008 signal carrying `event=api_error` instead of `event=idle`

#### Scenario: Turn ends normally
- **WHEN** a Claude turn ends and the transcript tail contains no current-turn `isApiErrorMessage:true` entry
- **THEN** the `Stop` hook emits the normal `event=idle` signal

#### Scenario: Stale error from a prior turn is ignored
- **WHEN** an `isApiErrorMessage:true` entry exists but a later `type:user` (re-prompt) or later non-error `type:assistant` entry follows it
- **THEN** the hook treats the error as stale and emits `event=idle`

#### Scenario: Missing or unreadable transcript degrades gracefully
- **WHEN** `transcript_path` is absent, empty, or the file cannot be read
- **THEN** the hook emits the normal `event=idle` and never reports a false error

### Requirement: Compaction is surfaced from the native PreCompact hook

Supacode SHALL map the Claude Code `PreCompact` hook to a presence signal `event=compacting`. Supacode SHALL NOT map `PostCompact`, because compaction finishing is not turn completion.

#### Scenario: Compaction begins
- **WHEN** Claude Code fires the `PreCompact` hook for a session
- **THEN** Supacode emits an OSC 3008 signal carrying `event=compacting` for that surface

#### Scenario: PostCompact does not complete the turn
- **WHEN** Claude Code fires `PostCompact`
- **THEN** Supacode does not emit a turn-completion or idle signal from that event

### Requirement: New presence events flow through the existing pipeline

The presence event model SHALL include `api_error` and `compacting` event names, and `AgentPresenceFeature` SHALL handle them: an `api_error` event marks the agent as errored, and a `compacting` event marks it as compacting. These events SHALL propagate through the same OSC 3008 → `WorktreeTerminalState` → `AgentPresenceFeature` → per-leaf `SidebarItemFeature.State` fan-out used by existing presence events, without introducing a new transport.

#### Scenario: api_error event marks the session errored
- **WHEN** an `api_error` OSC 3008 signal is received for a surface
- **THEN** `AgentPresenceFeature` records an errored state for that surface and the owning sidebar leaf's `agentError` state is set

#### Scenario: compacting event marks the session compacting
- **WHEN** a `compacting` OSC 3008 signal is received for a surface
- **THEN** `AgentPresenceFeature` records a transient compacting state for that surface

### Requirement: Errored session shows a distinct sidebar indicator and floats to the top

A sidebar leaf whose session is errored SHALL display a distinct red warning badge (`exclamationmark.triangle`) with a tooltip indicating the session needs a manual restart, visually distinct from the existing orange unread-notification indicator. The errored leaf SHALL be classified into the highest-priority Active-rail bucket so it floats above unread / awaiting-input / running sessions. A compacting session SHALL show a subtle transient indicator with no priority float and no error styling.

#### Scenario: Error badge and float
- **WHEN** a sidebar leaf's `agentError` state is set
- **THEN** the row renders the red `exclamationmark.triangle` badge with a "needs manual restart" tooltip and is placed in the top-priority Active-rail bucket

#### Scenario: Compacting indicator is subtle
- **WHEN** a sidebar leaf is in the compacting state
- **THEN** the row shows a subtle transient compacting indicator and does not float to the top or use error styling

### Requirement: Error indicator clears on restart or focus

The `agentError` state SHALL clear when the surface's next `busy` or `session_start` event arrives (agent restarted / re-prompted) or when the user focuses that session's tab. The transient compacting state SHALL clear on the surface's next `busy` or `idle` event.

#### Scenario: Restart clears the error
- **WHEN** an errored surface receives a subsequent `busy` or `session_start` event
- **THEN** the `agentError` state is cleared and the red badge is removed

#### Scenario: Focus clears the error
- **WHEN** the user focuses the tab of an errored session
- **THEN** the `agentError` state is cleared

### Requirement: API error raises a menu-bar notification

When a session becomes errored, Supacode SHALL add an entry to the existing menu-bar notification status item so the user is alerted when the app is unfocused.

#### Scenario: Menu-bar entry on error
- **WHEN** a surface transitions into the errored state
- **THEN** an entry identifying that session is added to the menu-bar notification list
