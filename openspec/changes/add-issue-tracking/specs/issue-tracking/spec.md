# issue-tracking

## ADDED Requirements

### Requirement: Repository issue list

The system SHALL fetch the open GitHub issues of a tracked repository (the same remote repository the pull request integration resolves) via the `gh` CLI, up to the 50 most recently updated, and expose for each issue: number, title, URL, author login, labels (name and color), comment count, and last-updated time.

#### Scenario: Issues load for a repository

- **WHEN** issue polling fires for a repository with open issues on its resolved remote
- **THEN** the reducer stores the fetched issues for that repository, ordered by last-updated descending

#### Scenario: Fork checkout resolves to upstream

- **WHEN** the local checkout is a fork with an upstream remote
- **THEN** the issue query targets the upstream repository, matching the pull request integration's remote resolution

#### Scenario: Remote repository is skipped

- **WHEN** issue polling would fire for a repository that is not a local checkout
- **THEN** no issue fetch is performed

### Requirement: Issue polling lifecycle

Issue polling SHALL reuse the worktree info watcher's scheduling: per-repository tasks at the focused interval when a worktree of that repository is selected and the unfocused interval otherwise, and SHALL stop when GitHub integration is disabled or the repository is removed.

#### Scenario: Integration toggled off

- **WHEN** `githubIntegrationEnabled` is turned off
- **THEN** all issue polling tasks are cancelled and no further issue fetches occur

#### Scenario: Repository removed

- **WHEN** a repository is removed from the sidebar
- **THEN** its issue polling task is cancelled and its issue state is discarded

### Requirement: Issue inspector pane

The status inspector SHALL offer an Issues pane alongside the existing Pull Request pane, listing the repository's open issues with number, title, labels, comment count, and relative updated time. Selecting an issue SHALL open its GitHub page in the browser.

#### Scenario: Issues displayed

- **WHEN** the user switches the status inspector to the Issues pane and issues are loaded
- **THEN** the issue list renders with number, title, labels, comment count, and updated time

#### Scenario: Empty state

- **WHEN** the Issues pane is shown and the repository has no open issues
- **THEN** a "No Open Issues" empty state is displayed

#### Scenario: Open on GitHub

- **WHEN** the user clicks an issue row
- **THEN** the issue's URL opens in the default browser

### Requirement: Issue update notifications

The system SHALL detect, between consecutive polls of the same repository, newly created issues, increased comment counts, and changed label sets, and SHALL surface each as an in-app notification in the existing notification bell, grouped under the repository. Notifications SHALL only be produced when `inAppNotificationsEnabled` is on.

#### Scenario: New comment detected

- **WHEN** a poll returns an issue whose comment count is greater than the previous snapshot
- **THEN** a notification "New comment on #N" is added to the bell for that repository

#### Scenario: Label change detected

- **WHEN** a poll returns an issue whose label set differs from the previous snapshot
- **THEN** a notification describing the label change for #N is added to the bell

#### Scenario: New issue detected

- **WHEN** a poll returns an issue number absent from an existing snapshot
- **THEN** a "New issue #N" notification is added to the bell

#### Scenario: First load does not notify

- **WHEN** the first successful issue fetch for a repository completes
- **THEN** the snapshot is seeded and no notifications are produced

#### Scenario: Notification opens the issue

- **WHEN** the user clicks an issue notification in the bell popover
- **THEN** the issue's GitHub page opens in the browser and the notification is marked read
