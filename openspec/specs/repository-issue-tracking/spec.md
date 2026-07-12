# repository-issue-tracking Specification

## Purpose
TBD - created by archiving change scope-issue-tracking-to-involved. Update Purpose after archive.
## Requirements
### Requirement: Signed-in GitHub login resolution

The system SHALL resolve the signed-in GitHub login for a repository's host from the existing `authStatus()` and cache it for use in issue queries. When no signed-in login is available, the involved-issue set SHALL be empty and no issue notifications SHALL fire.

#### Scenario: Login available

- **WHEN** the repository's host has an active authenticated GitHub account
- **THEN** the system uses that account's login to build the involved-issue query

#### Scenario: No login available

- **WHEN** no authenticated GitHub account exists for the repository's host
- **THEN** the involved-issue set is empty
- **AND** no issue notifications are produced

#### Scenario: Login refreshes after auth change

- **WHEN** the GitHub authentication changes (sign in, sign out, or account switch)
- **THEN** the cached login is updated so subsequent polls use the current login

### Requirement: Issue data fetch

The system SHALL fetch, in a single GraphQL request per repository per poll, two issue sets: the **All** set (the repository's open issues ordered by most-recently-updated) and the **Mine** set (issues the signed-in login is involved in, via GitHub `involves:` semantics, including both open and closed issues). Each fetched issue SHALL carry its number, title, url, updatedAt, author login, labels, comment count, and open/closed state.

#### Scenario: Single combined request

- **WHEN** a repository issue poll runs and a signed-in login is available
- **THEN** both the All set and the Mine set are retrieved in one GraphQL request
- **AND** the request count does not increase relative to fetching the All set alone

#### Scenario: Involved set membership

- **WHEN** the Mine set is fetched for login `L`
- **THEN** it contains exactly the issues where `L` is the author, an assignee, a mentioned user, or a commenter
- **AND** it includes issues in both open and closed state

#### Scenario: State captured per issue

- **WHEN** an issue is decoded from either set
- **THEN** its open/closed state is available for notification diffing and list filtering

### Requirement: Notifications scoped to involved issues

The system SHALL derive issue notifications only from the Mine set. The whole-repository activity window SHALL NOT produce notifications. This prevents unrelated issues that re-enter a most-recently-updated window from being reported as new.

#### Scenario: Unrelated activity produces no notification

- **WHEN** an issue the user is not involved in gains a comment, label, or state change
- **THEN** no notification is produced

#### Scenario: No false "new issue" from window churn

- **WHEN** an issue the user is not involved in re-enters the repository activity window after being absent
- **THEN** no `New issue` notification is produced

### Requirement: Involved-issue notification events

For issues in the Mine set, the system SHALL produce a notification when, compared to the previous poll's snapshot of the Mine set, an issue's comment count increases (new comment), its label set changes (label change), or its open/closed state changes (closed or reopened). The notification SHALL identify the issue by number and carry its title and url.

#### Scenario: New comment

- **WHEN** an involved issue's comment count is greater than the previous snapshot's
- **THEN** a "new comment on #N" notification is produced

#### Scenario: Label change

- **WHEN** an involved issue's label set differs from the previous snapshot's
- **THEN** a "labels changed on #N" notification describing the added and removed labels is produced

#### Scenario: Closed

- **WHEN** an involved issue transitions from open to closed
- **THEN** an "issue #N closed" notification is produced

#### Scenario: Reopened

- **WHEN** an involved issue transitions from closed to open
- **THEN** an "issue #N reopened" notification is produced

### Requirement: First-appearance notification for newly involved issues

When an issue newly enters the Mine set (present in the current poll but absent from the previous Mine snapshot), the system SHALL produce a single "you're involved in #N" notification if the issue was NOT authored by the signed-in user, and SHALL produce no notification if the issue WAS authored by the signed-in user. This event SHALL NOT be produced on the first successful poll.

#### Scenario: Newly mentioned or assigned

- **WHEN** an issue not authored by the user newly enters the Mine set on a poll that has a previous snapshot
- **THEN** a "you're involved in #N" notification is produced

#### Scenario: User's own newly created issue

- **WHEN** an issue authored by the user newly enters the Mine set
- **THEN** no notification is produced for its appearance

### Requirement: Silent seeding on first poll

The first successful issue poll for a repository SHALL seed the Mine snapshot without producing any notifications. Notifications SHALL only be produced on subsequent polls that have a previous snapshot to diff against.

#### Scenario: First poll seeds silently

- **WHEN** the first successful issue poll for a repository completes
- **THEN** the Mine snapshot is stored
- **AND** no notifications are produced regardless of the involved issues present

### Requirement: Issue list scope and state filtering

The status inspector issue list SHALL provide a primary scope selector with values **All** and **Mine**, defaulting to All. When **All** is selected the list SHALL show the All set. When **Mine** is selected the list SHALL show the Mine set and SHALL provide a secondary state filter with values **All states**, **Open**, and **Closed**, defaulting to All states. The secondary state filter SHALL be visible only when Mine is selected.

#### Scenario: Default scope

- **WHEN** the issue list is first shown
- **THEN** the scope is All and the All set (open repository issues) is displayed

#### Scenario: Switch to Mine

- **WHEN** the user selects the Mine scope
- **THEN** the Mine set is displayed, including closed issues
- **AND** the secondary state filter appears, defaulting to All states

#### Scenario: Filter Mine by state

- **WHEN** the user selects Open (or Closed) in the secondary state filter while in Mine scope
- **THEN** only open (or closed) issues from the Mine set are displayed

#### Scenario: Secondary filter hidden in All scope

- **WHEN** the scope is All
- **THEN** the secondary state filter is not shown

### Requirement: Notification pruning for removed repositories

When a repository is no longer tracked, the system SHALL remove its issue notifications and its Mine snapshot so stale notifications do not persist.

#### Scenario: Repository removed

- **WHEN** a repository is removed from tracking
- **THEN** its issue notifications are cleared
- **AND** its Mine snapshot is discarded

