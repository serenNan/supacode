import ComposableArchitecture
import SupacodeSettingsFeature
import SwiftUI

/// Contents of the notification menu bar extra: newest unread notifications on
/// top, bulk actions, then app-level items. Rendered with the native `.menu`
/// style, so rows are plain menu items (title + subtitle Texts), not custom
/// chrome; the richer 3-line layout stays in the inspector pane.
struct MenuBarNotificationsMenu: View {
  let store: StoreOf<AppFeature>
  @Environment(\.openURL) private var openURL

  var body: some View {
    let list = MenuBarNotificationList.compute(groups: store.repositories.toolbarNotificationGroupsCache)
    // Menus are rebuilt each time they open, so a plain Date() keeps the
    // relative timestamps fresh without a ticking TimelineView.
    let now = Date()
    Group {
      if list.items.isEmpty {
        Text("No Unread Notifications")
      } else {
        ForEach(list.items) { item in
          Button {
            select(item)
          } label: {
            Text(item.headline)
            Text(verbatim: subtitle(for: item, now: now))
          }
          .help("Open this notification.")
        }
      }
      Divider()
      Button("Show Notifications") {
        store.send(.showNotificationsPane)
      }
      .help("Open the notifications pane in the main window.")
      Button("Jump to Latest Unread") {
        store.send(.jumpToLatestUnread)
      }
      .disabled(!list.hasUnread)
      .help("Focus the terminal that sent the newest unread notification.")
      Button("Mark All as Read") {
        store.send(.markAllNotificationsRead)
      }
      .disabled(!list.hasUnread)
      .help("Mark every notification as read.")
      Button("Clear All") {
        store.send(.clearAllNotifications)
      }
      .disabled(!list.hasAny)
      .help("Remove every notification.")
      Divider()
      Button("Check for Updates...") {
        store.send(.updates(.checkForUpdates))
      }
      .help("Check for Supacode updates.")
      Button("Settings...") {
        store.send(.settings(.setSelection(.general)))
      }
      .help("Open Supacode settings.")
      Divider()
      Button("Quit Supacode") {
        store.send(.requestQuit)
      }
      .help("Quit Supacode.")
    }
  }

  private func select(_ item: MenuBarNotificationItem) {
    switch item.kind {
    case .terminal(let worktreeID, let tabID, let surfaceID, let notificationID):
      store.send(
        .menuBarNotificationSelected(
          worktreeID: worktreeID, tabID: tabID, surfaceID: surfaceID, notificationID: notificationID
        )
      )
    case .issue(let notificationID, let url):
      store.send(.repositories(.issueNotificationSelected(notificationID)))
      if let url = URL(string: url) {
        openURL(url)
      }
    }
  }

  private func subtitle(for item: MenuBarNotificationItem, now: Date) -> String {
    let time = Self.relativeTime(item.createdAt, now: now)
    return item.detail.isEmpty ? time : "\(time) · \(item.detail)"
  }

  private static func relativeTime(_ date: Date, now: Date) -> String {
    guard now.timeIntervalSince(date) >= 60 else { return "now" }
    return date.formatted(.relative(presentation: .named, unitsStyle: .narrow))
  }
}

/// Status item label: plain bell, badged while anything is unread. Kept as its
/// own view so notification churn invalidates just this label.
struct MenuBarNotificationsLabel: View {
  let store: StoreOf<AppFeature>

  var body: some View {
    let hasUnread = store.repositories.toolbarNotificationGroupsCache.contains { $0.unreadCount > 0 }
    Image(systemName: hasUnread ? "bell.badge" : "bell")
      .accessibilityLabel(hasUnread ? "Supacode notifications, unread" : "Supacode notifications")
  }
}
