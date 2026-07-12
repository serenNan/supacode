import Foundation
import IdentifiedCollections
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct MenuBarNotificationListTests {
  @Test func flattensUnreadNewestFirstAndCapsAtMaxItems() {
    let base = Date(timeIntervalSinceReferenceDate: 1_000)
    let notifications = (0..<12).map { index in
      WorktreeTerminalNotification(
        surfaceID: UUID(),
        title: "terminal",
        body: "body \(index)",
        createdAt: base.addingTimeInterval(Double(index))
      )
    }
    let list = MenuBarNotificationList.compute(groups: [
      makeGroup(worktrees: [makeWorktreeGroup(notifications: notifications)])
    ])

    #expect(list.items.count == MenuBarNotificationList.maxItems)
    #expect(list.items.first?.detail == "body 11")
    #expect(list.items.last?.detail == "body 2")
    #expect(list.hasUnread)
    #expect(list.hasAny)
  }

  @Test func skipsReadNotificationsButStillReportsHasAny() {
    let notification = WorktreeTerminalNotification(
      surfaceID: UUID(),
      title: "terminal",
      body: "done",
      createdAt: Date(timeIntervalSinceReferenceDate: 0),
      isRead: true
    )
    let list = MenuBarNotificationList.compute(groups: [
      makeGroup(worktrees: [makeWorktreeGroup(notifications: [notification])])
    ])

    #expect(list.items.isEmpty)
    #expect(!list.hasUnread)
    #expect(list.hasAny)
  }

  @Test func emptyGroupsProduceEmptyList() {
    let list = MenuBarNotificationList.compute(groups: [])
    #expect(list.items.isEmpty)
    #expect(!list.hasUnread)
    #expect(!list.hasAny)
  }

  @Test func agentNotificationHeadlinesSessionTitle() {
    let tabID = TerminalTabID()
    let notification = WorktreeTerminalNotification(
      surfaceID: UUID(),
      tabID: tabID,
      title: "claude",
      body: "needs your permission",
      createdAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let list = MenuBarNotificationList.compute(groups: [
      makeGroup(worktrees: [
        makeWorktreeGroup(notifications: [notification], tabTitles: [tabID: "fix login bug"])
      ])
    ])

    #expect(list.items.first?.headline == "fix login bug")
  }

  @Test func agentNotificationWithoutSessionTitleFallsBackToDisplayName() {
    let notification = WorktreeTerminalNotification(
      surfaceID: UUID(),
      title: "claude",
      body: "done",
      createdAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let list = MenuBarNotificationList.compute(groups: [
      makeGroup(worktrees: [makeWorktreeGroup(notifications: [notification])])
    ])

    #expect(list.items.first?.headline == "Claude Code")
  }

  @Test func terminalItemCarriesFocusCoordinates() {
    let surfaceID = UUID()
    let tabID = TerminalTabID()
    let notification = WorktreeTerminalNotification(
      surfaceID: surfaceID,
      tabID: tabID,
      title: "claude",
      body: "done",
      createdAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let list = MenuBarNotificationList.compute(groups: [
      makeGroup(worktrees: [makeWorktreeGroup(id: "/tmp/repo/wt", notifications: [notification])])
    ])

    #expect(
      list.items.first?.kind
        == .terminal(
          worktreeID: "/tmp/repo/wt",
          tabID: tabID,
          surfaceID: surfaceID,
          notificationID: notification.id
        )
    )
  }

  @Test func issueNotificationCarriesRepositoryNameAndURL() {
    let issue = RepositoryIssueNotification(
      id: UUID(),
      repositoryID: "/tmp/repo",
      issueNumber: 42,
      title: "New comment on #42",
      body: "Fix crash on launch",
      url: "https://github.com/a/b/issues/42",
      createdAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    let list = MenuBarNotificationList.compute(groups: [
      makeGroup(name: "supacode", issueNotifications: [issue])
    ])

    let item = list.items.first
    #expect(item?.headline == "New comment on #42")
    #expect(item?.detail == "supacode · Fix crash on launch")
    #expect(item?.kind == .issue(notificationID: issue.id, url: "https://github.com/a/b/issues/42"))
  }

  private func makeGroup(
    name: String = "repo",
    worktrees: [ToolbarNotificationWorktreeGroup] = [],
    issueNotifications: [RepositoryIssueNotification] = []
  ) -> ToolbarNotificationRepositoryGroup {
    ToolbarNotificationRepositoryGroup(
      id: "/tmp/repo",
      name: name,
      color: nil,
      isFolder: false,
      worktrees: worktrees,
      issueNotifications: issueNotifications
    )
  }

  private func makeWorktreeGroup(
    id: Worktree.ID = "/tmp/repo/wt",
    notifications: [WorktreeTerminalNotification],
    tabTitles: [TerminalTabID: String] = [:]
  ) -> ToolbarNotificationWorktreeGroup {
    ToolbarNotificationWorktreeGroup(
      id: id,
      name: "wt",
      notifications: notifications,
      hasUnseenNotifications: notifications.contains { !$0.isRead },
      tabTitles: tabTitles
    )
  }
}
