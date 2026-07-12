## Why

The current issue-tracking feature notifies on *every* open issue that shows activity, and it detects "new" issues by diffing a `first: 50, orderBy: UPDATED_AT DESC` window. On an active repository that window churns constantly, so unrelated issues re-entering the window are mislabeled `New issue #N` — producing a flood of irrelevant notifications (e.g. a batch of 15 old issues all appearing at once). The user is signed in to GitHub, so the only notifications that matter are ones about issues they are involved in. The list view also offers no way to focus on the user's own issues.

## What Changes

- **BREAKING (notification behavior)**: Stop generating notifications from the whole-repo activity window. Notifications now fire only for issues the signed-in user is **involved in** (author, assignee, mentioned, or commenter — GitHub `involves:` semantics).
- Fetch the involved-issue set via a reliable, complete `search(is:issue involves:<login>)` query instead of relying on the churning top-50 activity window, which eliminates the false `New issue` flood at its root.
- Notification events on an involved issue: **new comment**, **label change**, and **state change** (closed / reopened — newly tracked). A first-time appearance of a non-authored involved issue (someone @mentioned or assigned the user) fires a single "you're involved in #N" notification; issues the user authored are silent on first appearance. The first successful poll seeds silently.
- Resolve and cache the signed-in GitHub login (from the existing `authStatus()`), passed into the query. When no login is available, the involved set is empty and no notifications fire.
- **Issue list view** gains filtering: a primary scope toggle **All / Mine** (default All) and, within Mine, a secondary **state filter** (All states / Open / Closed, default All states). The Mine set includes closed issues.
- Track issue `state` (OPEN/CLOSED) through the model, GraphQL response, and snapshot diff to support state-change detection and the Closed filter.

## Capabilities

### New Capabilities
- `repository-issue-tracking`: Tracking a repository's GitHub issues in the status inspector — how the involved-issue set is fetched, how update notifications are derived and scoped to the signed-in user, and how the inspector list is filtered by scope and state. (The feature exists in code but was never captured as an OpenSpec spec; this change writes the target behavior as its first spec.)

### Modified Capabilities
<!-- None: no existing OpenSpec spec covers issue tracking. -->

## Impact

- **Models**: `GithubIssue` (add `state`), `GithubIssuesGraphQLResponse` (add `search` alias + `state`, decode issue nodes from search results).
- **Client**: `GithubCLIClient.listIssues` / GraphQL query builder — combined single-request query for the All set and the involved set; login threaded in from `authStatus()`.
- **Reducer**: `RepositoriesFeature` — new state for the involved set and list-filter selection, cached GitHub login, rewritten notification derivation, pruning.
- **Business logic**: `RepositoryIssueUpdates` — diff the involved set, add state-change and first-appearance events, keep silent seeding.
- **Views**: `RepositoryIssuesInspectorView` / `WorktreeStatusInspector` — scope + state filter controls.
- **Tests**: `RepositoryIssueTrackingTests`, `GithubIssuesResponseTests`, `ToolbarNotificationGroupingTests`, `MenuBarNotificationListTests` updated; new coverage for involved-scoping, state changes, and filtering.
- **Rate limits**: no increase in request count — the All and involved sets are fetched in one GraphQL request per repo per poll (relevant to issue #615).
