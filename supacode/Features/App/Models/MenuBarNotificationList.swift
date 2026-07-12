import Foundation
import SupacodeSettingsShared

/// Flattened, menu-sized projection of the toolbar notification groups: the
/// newest unread items across every repository plus the flags the menu bar
/// extra needs to enable its bulk actions.
struct MenuBarNotificationList: Equatable {
  static let maxItems = 10

  var items: [MenuBarNotificationItem] = []
  /// True when any notification exists at all (read or unread), so "Clear All"
  /// stays enabled after everything was marked read.
  var hasAny = false
  /// True when any notification is unread. Tracked separately from `items`,
  /// which caps at `maxItems`.
  var hasUnread = false

  static func compute(groups: [ToolbarNotificationRepositoryGroup]) -> Self {
    var items: [MenuBarNotificationItem] = []
    var hasAny = false
    for group in groups {
      hasAny = hasAny || group.notificationCount > 0
      for issue in group.issueNotifications where !issue.isRead {
        items.append(
          MenuBarNotificationItem(
            id: issue.id,
            headline: issue.title,
            detail: "\(group.name) · \(issue.body)",
            createdAt: issue.createdAt,
            kind: .issue(notificationID: issue.id, url: issue.url)
          )
        )
      }
      for worktree in group.worktrees {
        for notification in worktree.notifications where !notification.isRead {
          items.append(
            MenuBarNotificationItem(
              id: notification.id,
              headline: notification.headline(sessionTitle: worktree.sessionTitle(for: notification)),
              detail: notification.body,
              createdAt: notification.createdAt,
              kind: .terminal(
                worktreeID: worktree.id,
                tabID: notification.tabID,
                surfaceID: notification.surfaceID,
                notificationID: notification.id
              )
            )
          )
        }
      }
    }
    items.sort { $0.createdAt > $1.createdAt }
    return Self(
      items: Array(items.prefix(maxItems)),
      hasAny: hasAny,
      hasUnread: !items.isEmpty
    )
  }
}

struct MenuBarNotificationItem: Identifiable, Equatable {
  enum Kind: Equatable {
    case terminal(
      worktreeID: Worktree.ID,
      tabID: TerminalTabID?,
      surfaceID: UUID,
      notificationID: UUID
    )
    case issue(notificationID: UUID, url: String)
  }

  let id: UUID
  let headline: String
  let detail: String
  let createdAt: Date
  let kind: Kind
}

extension WorktreeTerminalNotification {
  /// Display headline: agent notifications carry the agent slug as `title`, so
  /// headline with the live session (tab) title when one exists, else the agent
  /// display name. Non-agent notifications keep their own title (it's real
  /// content, not a slug).
  func headline(sessionTitle: String?) -> String {
    let agent = SkillAgent(rawValue: title.lowercased())
    let fallbackTitle = agent?.displayName ?? (title.isEmpty ? "Terminal" : title)
    // An unrenamed tab is titled with the bare process name ("claude"); map
    // that back to the display name rather than headlining the raw slug.
    let resolvedSessionTitle = sessionTitle.map { SkillAgent(rawValue: $0.lowercased())?.displayName ?? $0 }
    return (agent != nil ? resolvedSessionTitle : nil) ?? fallbackTitle
  }
}
