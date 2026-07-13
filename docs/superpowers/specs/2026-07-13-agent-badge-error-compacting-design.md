# Agent-badge-integrated error / compacting indicators

Fork-only design note (stripped before any upstream PR). Addresses the
maintainer review on supabitapp/supacode#647: move the API-error and
compaction indicators *onto the agent avatar badge* instead of rendering
them as separate sibling glyphs.

## Motivation

sbertix (#647): "a more Supacode approach would be to make the agent badge
background red and render the harness icon as `template`" for the error, and
"a similar indicator … always relating to the agent badge itself" for
compaction. Today the sidebar row renders a standalone red
`exclamationmark.triangle` (`AgentErrorBadge`) and a standalone spinner
(`CompactingIndicator`) beside the avatar group.

## Design

### Badge visual states (AgentBadgeView)

`AgentBadgeView` currently takes `awaitingInput: Bool`. It takes the richer
`AgentPresenceFeature.Activity` and maps it to a visual variant:

- `.errored` → circle background `.red` (was `.bar`), harness icon rendered
  `.renderingMode(.template)` in white; `.help("… needs a manual restart")`.
- `.compacting` → normal badge + a rotating arc stroked around the circle
  (`linear` `repeatForever`, gated on `accessibilityReduceMotion`, static arc
  when reduced); `.help("Compacting context…")`.
- `.awaitingInput` → existing colorScheme contrast-flip.
- `.busy` / `.idle` → normal.

Priority when more than one could apply: `errored` > `compacting` >
`awaitingInput`. Exposed as a pure `BadgeVisual` resolver
(`BadgeVisual.resolve(_ activity:)`) so the mapping + priority is unit-tested
without a SwiftUI host.

### Group ordering (AgentAvatarGroupView)

`Slot` carries `activity` (not just `awaitingInput`) and forwards it to the
badge. Sort order gains an errored-first key before the existing
awaiting-first key, so a broken agent leads the group (mirrors the row-level
float-to-top).

### Fallback when avatar badges are disabled (SidebarItemView.TrailingView)

`hasError` / `isCompacting` are badge-independent by design (the "needs
restart" warning must show even when the user turned avatar badges off),
whereas `agents(across:)` is gated on the badge toggle. So the standalone
`AgentErrorBadge` / `CompactingIndicator` are kept **only as a fallback**,
shown when `agents.isEmpty && (hasAgentError || isCompacting)` — i.e. there is
no avatar to carry the state. When the avatar group is present it carries the
error/compacting treatment itself and the sibling glyph is dropped.

### Per-tab sub-rows (TerminalTabLabelView)

The expanded per-tab sub-rows render the same avatar; they inherit the new
treatment through `AgentBadgeView` / the avatar group. Verified during
implementation; fallback applies identically per sub-row.

## Unchanged

Reducer + hook + OSC pipeline, the `.errored` / `.compacting` activities, the
`SidebarActiveClassification` float-to-top bucket, and the menu-bar
notification. This is a rendering-only change.

## Testing

- `BadgeVisual.resolve` — activity → variant + priority (errored > compacting
  > awaitingInput). Pure unit tests.
- Fallback predicate (`agents.isEmpty && (hasAgentError || isCompacting)`) —
  extracted as a pure helper and unit-tested.
- Reducer state flags already covered by existing tests.
- Everything visual (colors, ring animation, reduceMotion) verified by
  building and running the app.
