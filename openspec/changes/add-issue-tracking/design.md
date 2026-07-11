# Design: GitHub Issue Tracking

## Context

Supacode already tracks pull requests end to end: `GithubCLIClient.batchPullRequests` runs `gh api graphql` per repository (chunked by branch), `WorktreeInfoWatcherManager` schedules repo-keyed polling tasks (30s focused / 60s unfocused) and emits `WorktreeInfoWatcherClient.Event` over an `AsyncStream`, `RepositoriesFeature` consumes events and pushes results into per-leaf `SidebarItemFeature.State`, and `WorktreeGitInspectorView` renders the PR inspector pane.

Issues differ from PRs in one structural way: a PR maps to a branch (and therefore a worktree), while an issue belongs to the repository. The existing in-app notification pipeline (`WorktreeTerminalNotification` → `SidebarItemFeature.State.notifications` → `ToolbarNotificationGroup`) is entirely worktree/surface-scoped; there is no repo-level notification today.

This is built on the user's own fork, so we are free to extend models without upstream review.

## Goals / Non-Goals

**Goals:**

- Show open issues of the selected repository (the same remote the PR integration resolves, i.e. upstream for forks) in the status inspector.
- Keep the list fresh with the same polling cadence and lifecycle as PR tracking.
- Notify through the existing bell when a tracked issue gets a new comment, a label change, or when a new issue appears.
- Gate everything on the existing `githubIntegrationEnabled` setting and `GithubIntegrationClient.isAvailable` cache.

**Non-Goals:**

- Cross-repo participation inbox; issue mutation (create/comment/close); macOS system notifications; sidebar issue badges (avoids the per-leaf invalidation work for a repo-scoped concern — can be a follow-up).

## Decisions

### D1: Fetch via one GraphQL query per repository

`gh api graphql` with `repository(owner:, name:) { issues(first: 50, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { number title url updatedAt author { login } labels(first: 10) { nodes { name color } } comments { totalCount } } } }`.

- Why not `gh issue list --json`: its `comments` field returns full comment bodies (heavy); GraphQL gives `comments.totalCount` directly, and we already have the `gh api graphql` invocation, 504-retry, and `GithubCLIOutput` decoding infrastructure to reuse.
- New endpoint `GithubCLIClient.listIssues(host:owner:repo:) async throws -> [GithubIssue]`, resolving owner/repo the same way `batchPullRequests` does (upstream tier first), so a fork checkout tracks the upstream repo's issues — which is where the user's issues actually live.
- New model `GithubIssue: Decodable, Equatable, Hashable, Identifiable` with `number, title, url, updatedAt, authorLogin, labels: [Label], commentsCount`.

### D2: Piggyback on the existing PR polling task (revised during implementation)

The PR polling task in `WorktreeInfoWatcherManager` is already repo-keyed, cadence-correct, and lifecycle-managed. `emitPullRequestRefresh` now also emits a new `repositoryIssueRefresh(repositoryRootURL: URL)` event — no parallel `issueTasks` map.

- Originally planned as a parallel task map; implementation showed that duplicates ~80 lines of scheduling/cancellation for identical semantics. Piggybacking makes disable/removal/stop behavior identical by construction.
- Alternative considered: a separate repo-level poller client. Rejected — duplicates worktree→repo bookkeeping, focus tracking, and stop/cleanup lifecycle.
- Remote (non-local-checkout) repositories are skipped in the reducer, matching the PR refresh guard.

### D3: Repo-scoped issue state lives in `RepositoriesFeature.State`, not in sidebar leaves

`issuesByRepositoryID: [Repository.ID: IdentifiedArrayOf<GithubIssue>]` plus in-flight/queued tracking mirroring `pendingPullRequestRefreshByRepositoryID` / `inFlightPullRequestRefreshRepositoryIDs`.

- Issues are repo-level data consumed only by the inspector pane, so the per-leaf `sidebarItems` rule does not apply (nothing fans out to sidebar rows). If sidebar badges are added later, that data must move into `SidebarItemFeature.State` per CLAUDE.md.

### D4: Update detection by snapshot diff in the reducer

Keep the previous poll's `[Issue.number: (commentsCount, labelNames)]` snapshot per repository. On each `repositoryIssuesLoaded`:

- issue number not in snapshot **and snapshot exists** → "New issue #N: title"
- `commentsCount` increased → "New comment on #N: title"
- label set changed → "Labels changed on #N: title (+ready)"
- The very first successful load per repo seeds the snapshot **without notifying** (prevents a notification storm on app launch).

Diffing in the reducer (pure, testable) rather than in the watcher keeps the watcher a dumb scheduler, consistent with PR flow.

### D5: New repo-level notification model merged into the existing bell

Add `RepositoryIssueNotification { id, repositoryID, issueNumber, title, body, url, createdAt, isRead }` stored in `RepositoriesFeature.State`, and extend `computeToolbarNotificationGroups()` so each `ToolbarNotificationRepositoryGroup` can carry issue notifications in addition to its worktree groups. The popover renders them as a repo-level section; clicking opens the issue URL.

- Alternative considered: reuse `WorktreeTerminalNotification` by faking a `surfaceID`. Rejected — it would leak terminal semantics (surface focus, mute-active-surface behavior) into repo-scoped data and pollute the terminal model.
- Gated on `inAppNotificationsEnabled`, same as terminal notifications. Unread state feeds the bell's badge the same way `hasUnseenNotifications` does today.

### D6: UI — a Pull Request / Issues switcher in the status inspector

Extend `WorktreeStatusInspector` with a segmented picker: the existing PR pane and a new `RepositoryIssuesInspectorView` listing issues (number, title, labels as colored tags, comment count, relative updated time). Row click opens GitHub; empty state uses `ContentUnavailableView("No Open Issues", ...)`; loading state mirrors "Checking for pull request…". System colors only, Dynamic Type, tooltips per UX standards.

## Risks / Trade-offs

- [Notification noise on busy repos: every comment on any open issue notifies] → v1 accepts this (target use is the user's own repos); the diff function takes an optional author filter parameter so a "only my issues" filter is a one-line follow-up.
- [50-issue cap: updates to issues outside the newest 50 are invisible] → ordered by UPDATED_AT desc, so any updated issue re-enters the window; an issue leaving the window is not treated as closed (snapshot entries for absent issues are retained, not diffed).
- [GraphQL rate limits: one extra query per repo per 30/60s] → same budget class as PR polling, which already runs chunked queries at this cadence; issues add one query per repo.
- [Fork vs upstream repo resolution mismatch] → reuse the exact remote-resolution helper the PR path uses (`GithubRemoteInfo` tiers) instead of reimplementing.

## Open Questions

- None blocking. Deferred: sidebar issue badges, author-filtered notifications, closed-issue visibility.
