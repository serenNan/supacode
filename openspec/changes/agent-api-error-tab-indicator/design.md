## Context

Supacode surfaces agent liveness on the sidebar entirely through a hook-driven pipeline: Supacode installs Claude Code hooks in `~/.claude/settings.json` (`ClaudeHookSettings.hooksByEvent()`), each hook is a **pure-shell one-liner** that reads the hook JSON on stdin, extracts fields with a portable `awk` pass (`AgentPresenceOSC.notifyExtractAwk`), and emits an **OSC 3008** presence sequence to the surface's `$__tty`. The app receives it in `WorktreeTerminalState`, routes it through `AgentPresenceFeature` (`Activity: busy | awaitingInput | idle`), and fans it out to `SidebarItemFeature.State` per leaf. No terminal scrollback is ever scanned.

The gap: when a Claude turn dies with an API error, Claude Code **does not** emit `StopFailure`. It synthesizes the error as a fake assistant message tagged `isApiErrorMessage:true` in the transcript JSONL and emits an ordinary `Stop` hook. Supacode's `Stop` hook is a fixed emitter (`event=idle`), so the errored session is indistinguishable from a completed one. Compaction (`PreCompact`) is a native Claude Code hook that Supacode maps to nothing.

The reference implementation clawd-on-desk (`hooks/clawd-hook.js`) solves the same problem by reading the transcript tail on `Stop` and upgrading `Stop → ApiError` when a current-turn `isApiErrorMessage` entry exists. This design ports that mechanism into Supacode's shell-hook + OSC pipeline.

## Goals / Non-Goals

**Goals:**
- Detect a Claude API/connection error at turn end and mark the session on its sidebar tab as "needs manual restart" (distinct red badge, floats to top of Active rail).
- Surface `PreCompact` as a transient "compacting" tab state.
- Raise a menu-bar notification for the error.
- Reuse the existing hook → OSC 3008 → presence → sidebar pipeline; add only new events, not a new transport.
- Keep detection structural (transcript flag), robust to ANSI/scrollback, and SSH-portable (no `jq`/`python`).

**Non-Goals:**
- Surfacing the error *type* (rate_limit / server_error / …) in the UI — one red "needs restart" badge only. The hook may carry the type for logs but the UI ignores it.
- Auto-restarting the session.
- Detecting API errors for non-Claude agents (Codex/Kimi/…). Only Claude Code writes `isApiErrorMessage`; other agents are out of scope.
- Scanning raw terminal scrollback text.

## Decisions

### Decision 1 — Detect via transcript `isApiErrorMessage`, not terminal text
Detection reads the Claude Code transcript JSONL (structured) rather than the terminal scrollback. **Why:** the flag is exact and stable across ANSI/wrapping/scroll; the app already has a hook fired at exactly the right moment (`Stop`). **Alternative rejected:** read the surface scrollback via `ghostty_surface_read_text` and regex `^API Error:`. That needs a new terminal-text-reading capability, a polling trigger (no "output changed" callback exists), and is fragile against wrapping/scroll-off. Structural wins.

### Decision 2 — Run detection inside the `Stop` hook command, emit a new OSC event
The transcript scan lives in the installed `Stop` shell hook, which then emits `event=api_error` (on match) or the normal `event=idle`. The Swift app is unchanged except for handling one new event name. **Why:** mirrors clawd; the hook already receives `transcript_path` on stdin, so no new "which file is this session's transcript?" resolution is needed in-app; works identically local and over SSH. **Alternative rejected:** have the Swift app locate and tail the transcript itself (resolve `~/.claude/projects/<encoded-pwd>/*.jsonl` from OSC-7 pwd, watch the file). More moving parts, races on file discovery, and duplicates state the hook already holds.

### Decision 3 — Pure-`awk` current-turn transcript scan
The `Stop` hook reads the last N KB of `transcript_path` and, in one `awk` pass, finds the **last** line containing `"isApiErrorMessage":true` and confirms no **later** line is `"type":"user"` or a non-error `"type":"assistant"` (the clawd "current turn" gate — a later user re-prompt or clean assistant reply means the error is stale). Match ⇒ emit `api_error`. **Why awk:** Supacode hooks forbid `jq`/`python` for SSH portability; the existing `notifyExtractAwk` proves flat-JSON awk parsing is viable. On a truncated tail read the first (partial) line is dropped, as clawd does. Tail is bounded (a few KB) to keep hook latency low.

### Decision 4 — Error state is sticky; compacting is transient
`api_error` sets a sticky `SidebarItemFeature.State.agentError` that persists (so the tab keeps warning) until the surface's next `busy` / `session_start` (agent restarted / re-prompted) **or** the user focuses that tab. `compacting` is a transient presence state released by the next `busy`/`idle`. **Why:** an error the user hasn't acted on must not silently vanish; compaction self-resolves.

### Decision 5 — Top-priority classification + distinct styling
`SidebarActiveClassification` gains a new highest bucket for `agentError`, so an errored session floats above unread/awaiting/running in the Active rail. The badge is a red `exclamationmark.triangle` with a "needs manual restart" tooltip — visually distinct from the orange unread-notification dot. Compacting reuses a subtle transient indicator with no priority float and no error styling. The error also appends to `MenuBarNotificationList`.

## Risks / Trade-offs

- **CC transcript format dependency** (`isApiErrorMessage`, `error` field; observed CC 2.1.150) → If the field is absent/renamed, the scan simply finds no match and falls back to `event=idle` — no false positives, graceful degradation. Same dependency clawd accepts.
- **awk current-turn-gate correctness** → Port clawd's exact algorithm (last-error-index, then scan forward for user / non-error assistant) and cover it with a transcript-fixture test. A partial tail read drops the first line to avoid parsing a truncated JSON object.
- **Hook latency** (extra file read + awk on every `Stop`) → Bound the tail to a few KB and do a single awk pass; `Stop` is not latency-critical.
- **Stale error after recovery** → The current-turn gate and the clear-on-`busy`/focus rules prevent a resolved error from lingering.
- **Focus clears an unseen error** → Intended: focusing the tab means the user has seen it. Restart also clears it.
- **Non-Claude agents** → They never emit `isApiErrorMessage`; their `Stop` hooks keep emitting `idle` unchanged. No regression.
