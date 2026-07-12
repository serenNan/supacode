# Add GitHub Issue Tracking

## Why

Supacode's GitHub integration only tracks pull requests. Issues are invisible: a repo owner cannot see incoming issues without leaving the app, and a contributor cannot tell whether the maintainer has replied to an issue they filed (e.g. added a comment or a `ready` label). This forces constant context switching to `gh issue` or the GitHub website while working in Supacode.

This change is built for the user's own fork; it does not follow the upstream contribution process.

## What Changes

- Add an issue list panel for the selected repository, showing open issues (number, title, labels, author, updated time), reusing the visual language of the existing pull request panel.
- Clicking an issue opens it on GitHub in the browser.
- Poll issues via the `gh` CLI on the same cadence infrastructure as PR tracking (focused/unfocused intervals, pause when the GitHub integration is disabled).
- Detect updates on tracked issues (new comments, label changes) between polls and surface them through the existing in-app notification bell.
- Respect the existing `githubIntegrationEnabled` setting; no new global toggle.

Out of scope (explicitly not in this change):

- Cross-repo "my participation" inbox (issues/PRs the user authored on other repos).
- Creating, commenting on, closing, or otherwise mutating issues from within Supacode.
- System (macOS) notifications for issue updates.

## Capabilities

### New Capabilities

- `issue-tracking`: List open GitHub issues for a repository, keep the list fresh via polling, and notify on issue updates (new comments, label changes) through the in-app notification bell.

### Modified Capabilities

<!-- none: openspec/specs/ is empty; no existing capability specs to modify -->

## Impact

- **New code**: issue models + `gh issue`/GraphQL fetch support in `supacode/Clients/Github/`, an issue panel view in `supacode/Features/Repositories/Views/`, reducer state/actions for issue data.
- **Modified code**:
  - `GithubCLIClient` — new endpoint(s) for listing issues with labels and comment counts.
  - `WorktreeInfoWatcherManager` — a repo-level issue polling task alongside the existing PR tasks.
  - `RepositoriesFeature` reducer — issue state, refresh actions, diffing for update detection.
  - Notification path (`ToolbarNotificationGroup` / notification popover) — a new notification source for issue updates; issue notifications are repo-scoped rather than worktree-scoped, which the grouping model must accommodate.
- **Dependencies**: none new; reuses `gh` CLI, TCA, existing settings (`githubIntegrationEnabled`).
- **Tests**: reducer tests for issue refresh/diff/notification logic per project rules (`TestClock`-driven, no `Task.sleep`).
