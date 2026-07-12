## Context

Issue tracking (added in `ff59ac85`) polls a repository's issues on the pull-request refresh cadence (~30s focused / 60s unfocused), diffs consecutive polls, and produces notifications surfaced in the menu bar, toolbar notification group, and status inspector. Two problems:

1. **Notification derivation is unscoped.** Every open issue with activity notifies the user, which is noise since the user only cares about issues they are involved in.
2. **"New issue" detection is unreliable.** Issues are fetched with `issues(first: 50, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC})`. On an active repo the 50-item window churns; an issue that re-enters the window is absent from the previous snapshot and gets mislabeled `New issue #N`, causing floods of false notifications for old issues.

The app is authenticated to GitHub (`GithubCLIClient.authStatus()` already returns the active `username`/`host`), so we can scope both notifications and a new list filter to the signed-in user. `GithubIssue.authorLogin` already exists.

## Goals / Non-Goals

**Goals:**
- Notifications fire only for issues the signed-in user is involved in (author / assignee / mentioned / commenter).
- Eliminate the false `New issue` flood at its root by diffing a complete, stable set rather than a churning activity window.
- Add new-comment, label-change, and state-change (closed/reopened) notifications for involved issues, plus a first-appearance ping for newly involved (non-authored) issues.
- Issue list keeps showing all issues by default, with an opt-in filter to the user's involved issues, and a state filter (open/closed/all) within that.
- No increase in GitHub request count per poll.

**Non-Goals:**
- Native OS notifications (unchanged — still in-app menu bar / toolbar / inspector).
- Per-issue read/subscribe management beyond the existing mark-read-on-select.
- De-duplicating an involved issue that legitimately leaves and re-enters the Mine set (rare; see Risks).
- Reworking the pull-request tracking path that issues piggyback on for scheduling.

## Decisions

### D1. Fetch the involved set with GraphQL `search`, not `issues(filterBy:)`

GraphQL `issues(filterBy:)` exposes `createdBy`, `assignee`, and `mentioned` as *separate* filters and cannot OR them into a single "involved" set. GitHub search's `involves:<login>` qualifier means author OR assignee OR mention OR commenter — exactly the chosen scope. Use `search(query: "repo:<owner>/<name> is:issue involves:<login> sort:updated-desc", type: ISSUE, first: 50)`, decoding `... on Issue` nodes.

*Alternative considered:* three parallel `filterBy` queries unioned client-side — more requests, misses "commenter", rejected.

### D2. One combined GraphQL request for both sets

The query carries both the existing `repository(...).issues(...)` selection (All set, open, updated-desc) and a top-level `search(...)` selection (Mine set). One round trip per repo per poll → request count unchanged, respecting the rate-limit concern (issue #615). Both selections use `first: 50`.

*Alternative considered:* two separate client methods / two calls — cleaner separation but doubles requests, rejected for rate limits.

### D3. Login comes from cached `authStatus()`, threaded into the query

The signed-in login is required to build the `involves:` qualifier. `authStatus()` already returns it. Resolve it once, cache it in `RepositoriesFeature.State` (e.g. `githubLoginByHost` or a single `githubLogin`), refresh when GitHub auth changes. When absent, omit the `search` block from the query and treat the Mine set as empty (no notifications).

*Alternative considered:* a `viewer { login }` GraphQL sub-selection each poll — self-contained but adds a field every request and duplicates data we already have from `authStatus()`; rejected.

### D4. Notifications diff the Mine snapshot only; All set is display-only

`issueSnapshotsByRepositoryID` becomes a snapshot of the **Mine** set (keyed by issue number, storing `commentsCount`, `labelNames`, `state`). `RepositoryIssueUpdates.notifications` diffs Mine-vs-Mine. The All set feeds only the list view and never produces notifications. Because the Mine set is the *complete* set of the user's involved issues (not a global activity window), an issue leaving/re-entering it corresponds to real involvement changes, not window churn — so first-appearance is meaningful and there is no churn-driven flood.

### D5. Add `state` to the issue model and snapshot

`GithubIssue` gains `state` (open/closed). Needed for state-change notifications and the Closed list filter. `GithubIssuesGraphQLResponse` adds the `state` field and a `search` container decoding issue nodes. The snapshot compares `state` alongside `commentsCount` and `labelNames`.

### D6. First-appearance event rules

On a poll with a previous Mine snapshot, an issue present now but absent before:
- authored by the signed-in user → silent (they created it).
- not authored by the user → one "you're involved in #N" notification (covers @mention / assignment / someone-commented-so-you-followed cases).

The first successful poll (no previous snapshot) seeds silently regardless — preserving today's seeding behavior.

### D7. List filter selection is view-local UI state

The scope (`All`/`Mine`) and secondary state (`All states`/`Open`/`Closed`) selections are ephemeral presentation state with no side effects and no persistence need, so they live as `@State` in the issue-list view. The datasets they switch between (All set, Mine set) already live in reducer state. The secondary state control renders only when `Mine` is selected. This keeps the reducer free of pure-display state and avoids per-repository invalidation churn.

*Alternative considered:* reducer-held filter state — more testable but adds display-only state to the feature and per-repo invalidation for no behavioral gain; rejected.

## Risks / Trade-offs

- **Involved set larger than 50** → `sort:updated-desc, first:50` keeps the most recently active involved issues; inactive overflow is dropped. Mitigation: 50 active involved issues per repo is unlikely; revisit with pagination only if it bites.
- **An involved issue leaves then re-enters the Mine set** (e.g. involvement ended and later re-added, or >50 overflow) → its re-appearance fires "you're involved in #N" again. Mitigation: acceptable given rarity; a persistent seen-set could dedup later if needed.
- **Comment count as new-comment proxy** → a deleted+added comment nets zero, and comment edits don't bump the count, so some events are missed; matches current behavior. Mitigation: none for now; count is what the API cheaply exposes.
- **Login not yet resolved on early polls** → Mine set empty, no notifications until login is cached. Mitigation: resolve login eagerly (on repo load / auth change) so the gap is one poll at most.
- **Search rate budget** → GraphQL `search` counts against the GraphQL point budget; combined in one request keeps it to one call per repo per poll, no worse than today.

## Migration Plan

- No data migration. Snapshots are in-memory and reseed on next poll.
- On first run after the change, the first poll reseeds the Mine snapshot silently, so no historical backlog of notifications appears.
- Rollback is a straight revert; no persisted schema changes.

## Open Questions

- None blocking. D6's first-appearance behavior was confirmed with the user (fire for non-authored involvement).
