## 1. Model & GraphQL layer

- [x] 1.1 Add `state` (open/closed enum or bool `isClosed`) to `GithubIssue`; update the memberwise call site in `GithubIssuesGraphQLResponse.IssueNode.issue`.
- [x] 1.2 Extend `GithubIssuesQuery` to a combined query: keep `repository(...).issues(first:50, states:[OPEN], orderBy: UPDATED_AT DESC)` (All set) and add a top-level `search(query: $searchQuery, type: ISSUE, first: 50)` selection decoding `... on Issue` nodes with number/title/url/updatedAt/state/author/labels/comments. Make it accept the search query string as a variable and be omittable when there is no login.
- [x] 1.3 Extend `GithubIssuesGraphQLResponse` with a `search` container and `state` decoding; expose `allIssues` and `involvedIssues` accessors.
- [x] 1.4 Update/extend `GithubIssuesResponseTests` for the new `state` field and the `search`/involved decoding (fixture JSON with both blocks, and the no-search variant).

## 2. Client

- [x] 2.1 Change `GithubCLIClient.listIssues` (or add a sibling) to return both sets — signature `(host, owner, repo, login?) -> (all: [GithubIssue], involved: [GithubIssue])` — building the `repo:<owner>/<name> is:issue involves:<login> sort:updated-desc` search string, and omitting the search block when `login` is nil (involved = []).
- [x] 2.2 Update the `testValue`/preview client and `GithubCLIClientTests` for the new shape.

## 3. Login resolution

- [x] 3.1 Add cached GitHub login to `RepositoriesFeature.State` (keyed by host or a single active login), populated from `authStatus()`.
- [x] 3.2 Resolve/refresh the login on repository load and on GitHub auth change; add an action + effect. Add a reducer test that it caches and refreshes.

## 4. Notification derivation (Mine set)

- [x] 4.1 Change `RepositoryIssueSnapshot` to include `state`; snapshot the **Mine** set instead of all issues.
- [x] 4.2 Rewrite `RepositoryIssueUpdates.notifications` to diff Mine-vs-Mine and emit: new comment, label change, state change (closed/reopened), and first-appearance "you're involved in #N" for non-authored newly-present issues (authored → silent). Keep silent seeding when `previous` is nil. Take the signed-in login as a parameter for the author check.
- [x] 4.3 Update `RepositoryIssueNotification` if needed (title strings for state/involved events) and confirm `body`/`url` still populate.
- [x] 4.4 Update `RepositoryIssueTrackingTests`: new-comment, label-change, closed, reopened, first-appearance (non-authored fires / authored silent), silent seed, and a window-churn regression (an unrelated issue re-entering the All set produces no notification).

## 5. Reducer wiring

- [x] 5.1 Split reducer state into the All set (`issuesByRepositoryID`, display-only) and the Mine set (new `involvedIssuesByRepositoryID`); snapshot/diff drives notifications from Mine only.
- [x] 5.2 Update `repositoryIssuesLoaded` (and its action payload) to carry both sets; feed the login into `RepositoryIssueUpdates.notifications`.
- [x] 5.3 Ensure removed-repository pruning clears notifications and the Mine snapshot for that repo (extend existing prune at `RepositoriesFeature.swift` line ~4683).
- [x] 5.4 Update `refreshRepositoryIssues` effect to pass the cached login and dispatch both sets.

## 6. List filtering UI

- [x] 6.1 Add scope selector (`All` / `Mine`, default All) to the issue list in `RepositoryIssuesInspectorView` / `WorktreeStatusInspector` as view-local `@State`.
- [x] 6.2 Add secondary state filter (`All states` / `Open` / `Closed`, default All states) shown only when `Mine` is selected.
- [x] 6.3 Render All set for All scope, Mine set (filtered by state selection) for Mine scope; give controls tooltips per UX standards.

## 7. Notification surfaces sanity

- [x] 7.1 Verify menu bar (`MenuBarNotificationList`), toolbar group (`ToolbarNotificationGroup`), and inspector rows still render the new event types; update `ToolbarNotificationGroupingTests` / `MenuBarNotificationListTests` if titles/shape changed.

## 8. Verification

- [x] 8.1 Ran the affected suites green: `RepositoryIssueTrackingTests`, `GithubIssuesResponseTests`, `GithubIssuesQueryTests`, `GithubCLIClientTests`, `ToolbarNotificationGroupingTests`, `MenuBarNotificationListTests` (0 failures). Full-suite run deferred (slow + known flaky duplicate-class harness).
- [x] 8.2 `make build-app` succeeds (Build Succeeded, 0 errors).
- [ ] 8.3 Manual check (needs an authed repo + live polling): notifications only for involved issues; no `New issue` flood from unrelated activity; list scope + state filter behave per spec.
