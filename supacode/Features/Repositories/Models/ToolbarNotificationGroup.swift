import Foundation
import IdentifiedCollections
import OrderedCollections
import SupacodeSettingsShared

struct ToolbarNotificationRepositoryGroup: Identifiable, Equatable {
  let id: Repository.ID
  let name: String
  // Sidebar identity so notification headers render like the sidebar rows.
  let color: RepositoryColor?
  let isFolder: Bool
  let worktrees: [ToolbarNotificationWorktreeGroup]
  /// Repo-scoped GitHub issue updates; issues have no owning worktree, so they
  /// sit beside the worktree groups rather than inside one.
  let issueNotifications: [RepositoryIssueNotification]

  var notificationCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + worktree.notifications.count
    } + issueNotifications.count
  }

  var unreadCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + worktree.notifications.count { !$0.isRead }
    } + issueNotifications.count { !$0.isRead }
  }

  var unseenWorktreeCount: Int {
    worktrees.reduce(0) { count, worktree in
      count + (worktree.hasUnseenNotifications ? 1 : 0)
    }
  }
}

struct ToolbarNotificationWorktreeGroup: Identifiable, Equatable {
  let id: Worktree.ID
  let name: String
  let notifications: [WorktreeTerminalNotification]
  let hasUnseenNotifications: Bool
  /// Live tab titles for the tabs referenced by `notifications`, resolved from
  /// the row's `tabsSummary` so a notification row can show the session name
  /// and track renames. Only referenced tabs are included, keeping the
  /// Equatable diff blind to title churn on unrelated tabs.
  var tabTitles: [TerminalTabID: String] = [:]

  /// Display title for a notification: the live title of its tab, or nil when
  /// the tab is gone / untitled (callers fall back to the agent name).
  func sessionTitle(for notification: WorktreeTerminalNotification) -> String? {
    notification.tabID.flatMap { tabTitles[$0] }
  }

  /// Notifications regrouped per session for the inspector's collapsed
  /// rendering. Derived from `notifications` (kept newest-first by
  /// `appendNotification`'s insert-at-0), so cluster order is the order each
  /// session last notified and no extra Equatable surface is added.
  var sessionClusters: [NotificationSessionCluster] {
    var order: [NotificationSessionKey] = []
    var byKey: [NotificationSessionKey: [WorktreeTerminalNotification]] = [:]
    for notification in notifications {
      let key = NotificationSessionKey(notification)
      if byKey[key] == nil {
        order.append(key)
      }
      byKey[key, default: []].append(notification)
    }
    return order.map { NotificationSessionCluster(id: $0, notifications: byKey[$0] ?? []) }
  }
}

/// Identity of a notification's session: its tab when recorded, else the
/// surface — so notifications from an already-closed tab still cluster with
/// their surface siblings instead of one row each.
enum NotificationSessionKey: Hashable {
  case tab(TerminalTabID)
  case surface(UUID)

  init(_ notification: WorktreeTerminalNotification) {
    self = notification.tabID.map(Self.tab) ?? .surface(notification.surfaceID)
  }
}

/// One session's notifications, newest first. The inspector renders `newest`
/// when collapsed and the rest behind an expand control.
struct NotificationSessionCluster: Identifiable, Equatable {
  let id: NotificationSessionKey
  let notifications: [WorktreeTerminalNotification]

  var newest: WorktreeTerminalNotification { notifications[0] }
  var olderCount: Int { notifications.count - 1 }
  /// Unread among the *hidden* (older) notifications only; the visible newest
  /// row already shows its own unread dot.
  var hiddenUnreadCount: Int { notifications.dropFirst().count { !$0.isRead } }
}

extension RepositoriesFeature.State {
  /// Reads notification data off the per-row `SidebarItemFeature.State`
  /// (populated via `terminalProjectionChanged`) instead of the live
  /// `WorktreeTerminalManager`, so this is a pure reducer-state computation.
  /// Cached on `toolbarNotificationGroupsCache`; views read the cache.
  func computeToolbarNotificationGroups() -> [ToolbarNotificationRepositoryGroup] {
    let repositoriesByID = Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) })
    var groups: [ToolbarNotificationRepositoryGroup] = []

    // `orderedRepositoryIDs()` is local-only (keyed off `repositoryRoots`); append
    // remote repositories (host-keyed ids) so their worktree notifications also
    // surface in the toolbar bell. Mirrors the sidebar grouping in
    // `RepositoriesFeature+Sidebar`.
    var orderedIDs = orderedRepositoryIDs()
    let coveredIDs = Set(orderedIDs)
    for repository in repositories where repository.host != nil && !coveredIDs.contains(repository.id) {
      orderedIDs.append(repository.id)
    }

    for repositoryID in orderedIDs {
      guard let repository = repositoriesByID[repositoryID] else {
        continue
      }

      let worktreeGroups: [ToolbarNotificationWorktreeGroup] =
        orderedWorktrees(in: repository).compactMap { worktree -> ToolbarNotificationWorktreeGroup? in
          guard let row = sidebarItems[id: worktree.id], !row.notifications.isEmpty else {
            return nil
          }
          return ToolbarNotificationWorktreeGroup(
            id: worktree.id,
            name: row.resolvedSidebarTitle ?? worktree.name,
            notifications: Array(row.notifications),
            hasUnseenNotifications: row.hasUnseenNotifications,
            tabTitles: Self.notificationTabTitles(
              notifications: row.notifications, tabs: row.tabsSummary.tabs
            )
          )
        }

      let issueNotifications = issueNotifications.filter { $0.repositoryID == repositoryID }
      if !worktreeGroups.isEmpty || !issueNotifications.isEmpty {
        let isFolder = !repository.isGitRepository
        // A folder's title / tint live on its synthetic row, not the repo
        // section; resolve there so a customized folder header matches the sidebar.
        let folderRow = isFolder ? sidebarItems[id: Repository.folderWorktreeID(for: repository.rootURL)] : nil
        let section = sidebar.sections[repositoryID]
        groups.append(
          ToolbarNotificationRepositoryGroup(
            id: repository.id,
            name: isFolder
              ? (folderRow?.resolvedSidebarTitle ?? repository.name)
              : Repository.sidebarDisplayName(custom: section?.title, fallback: repository.name),
            color: isFolder ? folderRow?.customTint : section?.color,
            isFolder: isFolder,
            worktrees: worktreeGroups,
            issueNotifications: Array(issueNotifications)
          )
        )
      }
    }

    return groups
  }

  /// Titles for the tabs the notifications point at, trimmed; blank titles are
  /// dropped so consumers fall back to the agent name instead of showing an
  /// empty headline.
  private static func notificationTabTitles(
    notifications: IdentifiedArrayOf<WorktreeTerminalNotification>,
    tabs: [WorktreeTabsSummary.Tab]
  ) -> [TerminalTabID: String] {
    let referencedTabIDs = Set(notifications.compactMap(\.tabID))
    guard !referencedTabIDs.isEmpty else { return [:] }
    var titles: [TerminalTabID: String] = [:]
    for tab in tabs where referencedTabIDs.contains(tab.id) {
      let trimmed = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        titles[tab.id] = trimmed
      }
    }
    return titles
  }
}
