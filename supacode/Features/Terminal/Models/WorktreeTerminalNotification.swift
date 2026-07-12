import Foundation

struct WorktreeTerminalNotification: Identifiable, Equatable, Sendable {
  let id: UUID
  let surfaceID: UUID
  /// Tab containing `surfaceID` at append time; lets the inspector resolve the
  /// live tab title so the row tracks agent/user renames. Nil when the surface
  /// belonged to no tab.
  let tabID: TerminalTabID?
  let title: String
  let body: String
  let createdAt: Date
  var isRead: Bool

  init(
    id: UUID = UUID(),
    surfaceID: UUID,
    tabID: TerminalTabID? = nil,
    title: String,
    body: String,
    createdAt: Date,
    isRead: Bool = false
  ) {
    self.id = id
    self.surfaceID = surfaceID
    self.tabID = tabID
    self.title = title
    self.body = body
    self.createdAt = createdAt
    self.isRead = isRead
  }

  var content: String {
    [title, body].filter { !$0.isEmpty }.joined(separator: " - ")
  }
}
