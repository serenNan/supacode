## 1. Branch & scaffolding

- [x] 1.1 Create a descriptively named working branch (not detached HEAD / generic name) for this change
- [x] 1.2 Locate exact anchors: `EventName` enum (`AgentHookSocketServer.swift:462`), `AgentPresenceOSC.HookEvent` + `action(for:)` + `emitShell`, `ClaudeHookSettings.hooksByEvent()` Stop/PreCompact entries, `AgentPresenceFeature.Activity`, `SidebarItemFeature.State`, `SidebarActiveClassification` (`SidebarStructure.swift:28`), `SidebarItemView.TrailingView/StatusIndicator`, `MenuBarNotificationList`

## 2. Hook-side: new OSC events + PreCompact mapping (SupacodeSettingsShared)

- [x] 2.1 Add `HookEvent` cases for `api_error` and `compacting` in `AgentPresenceOSC` with their `action(for:)` OSC action strings; add unit tests asserting `emitShell(.apiError)` / `.compacting` carry `event=api_error` / `event=compacting`
- [x] 2.2 Map Claude Code `PreCompact` → `event=compacting` in `ClaudeHookSettings.hooksByEvent()`; assert `PostCompact` is NOT mapped. Add test in `AgentHookCommandTests` (`PreCompact` group emits `event=compacting`)

## 3. Hook-side: transcript API-error scan in the Stop command

- [x] 3.1 Write the pure-`awk` transcript-tail scanner (bounded tail read, drop first line on truncation, find last `"isApiErrorMessage":true`, current-turn gate = no later `"type":"user"` / non-error `"type":"assistant"`). Independent reimplementation of the same approach as clawd `extractApiErrorFromEntries` (no code copied)
- [x] 3.2 Rewrite the Claude `Stop` hook command to: read stdin JSON, awk-extract `transcript_path`, run the scanner, emit `event=api_error` on match else `event=idle`. Keep SSH-portable (no `jq`/`python`); reuse `emitShell` + stdin-awk pattern
- [x] 3.3 Add `AgentHookCommandTests` cases: Stop command references `transcript_path` + the api-error path and still emits `event=idle` on the no-match branch
- [x] 3.4 Add a fixture-driven test that runs the awk scanner (via `Process`) against transcript JSONL fixtures — error-current-turn ⇒ api_error, stale-error ⇒ idle, no-error ⇒ idle, missing-file ⇒ idle

## 4. Event model & presence

- [x] 4.1 Add `EventName.apiError` and `EventName.compacting` to `AgentHookEvent` (`AgentHookSocketServer.swift`)
- [x] 4.2 Write failing `AgentPresenceFeature` tests: `api_error` event → errored state; `compacting` → transient compacting; errored clears on next `busy`/`session_start`; compacting clears on next `busy`/`idle`
- [x] 4.3 Extend `AgentPresenceFeature.Activity` / state machine (add `.errored` and `.compacting`, or a sticky `errored` flag + transient compacting) and `apply(event:)` to satisfy 4.2

## 5. Sidebar leaf state & fan-out

- [x] 5.1 Add `SidebarItemFeature.State.agentError` (sticky) + a compacting marker; add `SidebarItemFeature.Action` case(s) to set/clear; write failing reducer tests for set + clear-on-restart
- [x] 5.2 Add clear-on-focus: clear `agentError` when the session's tab gains focus; write reducer test
- [x] 5.3 Wire fan-out in `AppFeature` (mirror `agentSnapshotEffects`): route `api_error`/`compacting` per-surface into the leaf; carry through `TerminalClient.Event` / `WorktreeTerminalState` as needed; add AppFeature test for the routing

## 6. Classification (float to top)

- [x] 6.1 Write failing test: an errored leaf classifies into a new highest-priority Active bucket, above unread/awaiting/running
- [x] 6.2 Add the top bucket to `SidebarActiveClassification` (`SidebarStructure.swift`) and update `classify(_:)` to read `agentError`; make 6.1 pass

## 7. Rendering

- [x] 7.1 Render red `exclamationmark.triangle` badge + "needs manual restart" tooltip in `SidebarItemView` `TrailingView`/`StatusIndicator` when `agentError` set; keep it visually distinct from the orange unread dot
- [x] 7.2 Render a subtle transient compacting indicator (no float, no error styling)

## 8. Menu bar

- [x] 8.1 On transition into errored, append an entry to `MenuBarNotificationList` identifying the session; write a test for the entry-append path

## 9. Verify

- [x] 9.1 App builds (`build-for-testing` compiled the `supacode` app target + all test targets: `** TEST BUILD SUCCEEDED **`)
- [x] 9.2 Test suite green: supacodeTests 1361✓/0, supacodeGitTests AgentHookCommandTests 124✓/0 (real-shell awk/fixture/menu-bar), supacodeFeatureTests 568✓/0. One parallel-only crash cascade traced to the pre-existing duplicate `ComposableArchitecture.Logger` class flakiness (each "failed" test passes in isolation), not this change.
- [x] 9.3 End-to-end hook behavior verified via real-shell fixture tests (transcript `isApiErrorMessage` current-turn ⇒ `api_error`, stale/clean/missing ⇒ `idle`, fixed restart notify round-trips); UI behavior verified at state level (classification floats errored to top; leaf `hasAgentError` drives the badge). Live in-app visual smoke test left to the user (a real connection-drop can't be forced headlessly).
- [x] 9.4 `openspec validate agent-api-error-tab-indicator --strict` passes
