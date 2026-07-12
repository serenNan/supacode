## 1. Data layer (models + gh CLI)

- [x] 1.1 Add `GithubIssue` model (`number, title, url, updatedAt, authorLogin, labels, commentsCount`) in `supacode/Clients/Github/`, decoded from the GraphQL response shape; unit-test decoding with a JSON literal (mirror `GithubBatchPullRequestsTests`)
- [x] 1.2 Add `GithubCLIClient.listIssues(host:owner:repo:)` running one `gh api graphql` issues query (first 50, OPEN, UPDATED_AT desc), reusing `GithubCLIOutput` decoding, the 504 retry, and the same owner/repo remote resolution as `batchPullRequests`; unit-test the query construction and response parsing

## 2. Polling (WorktreeInfoWatcherManager)

- [x] 2.1 Add `repositoryIssueRefresh(repositoryRootURL:)` to `WorktreeInfoWatcherClient.Event`, emitted alongside the PR refresh from the existing repo-keyed schedule (revised per design D2: no parallel task map)
- [x] 2.2 TestClock-driven tests in `WorktreeInfoWatcherManagerTests`: interval switching on selection change, cancellation on disable and on repo removal (no `Task.sleep`)

## 3. Reducer (RepositoriesFeature)

- [x] 3.1 Add state: `issuesByRepositoryID`, per-repo snapshot `[issueNumber: (commentsCount, labelNames)]`, in-flight/queued tracking mirroring the PR refresh pattern; handle `repositoryIssueRefresh` → fetch effect → `repositoryIssuesLoaded`, skipping remote repos and gating on `GithubIntegrationClient.isAvailable`
- [x] 3.2 Implement snapshot diffing on `repositoryIssuesLoaded` producing `RepositoryIssueNotification`s (new issue / comment count increase / label change; first load seeds silently), gated on `inAppNotificationsEnabled`
- [x] 3.3 TestStore tests: load stores issues, first load doesn't notify, comment/label/new-issue diffs notify, integration-off produces nothing, repo removal clears state

## 4. Notifications (bell integration)

- [x] 4.1 Add `RepositoryIssueNotification` model and extend `ToolbarNotificationRepositoryGroup` / `computeToolbarNotificationGroups()` to carry repo-level issue notifications; unread count feeds the bell badge
- [x] 4.2 Render issue notifications as a repo-level section in `NotificationPopoverView`; click opens the issue URL and marks it read; extend `ToolbarNotificationGroupingTests`

## 5. Inspector UI

- [x] 5.1 Add a Pull Request / Issues segmented picker to `WorktreeStatusInspector` and a `RepositoryIssuesInspectorView` (rows: number, title, label tags with system colors, comment count, relative updated time; loading + `ContentUnavailableView("No Open Issues", ...)` empty states; tooltips, Dynamic Type)
- [x] 5.2 Wire row click to open the issue URL in the browser

## 6. Verification

- [x] 6.1 Run the full test suite and `make build-app`
- [ ] 6.2 Manual verification against the supacode repo itself: Issues pane lists #629/#630; add a comment to a test issue and confirm a bell notification appears within one poll interval
