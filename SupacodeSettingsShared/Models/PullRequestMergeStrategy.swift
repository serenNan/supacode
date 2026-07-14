import Foundation

public nonisolated enum PullRequestMergeStrategy: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
  case merge
  case squash
  case rebase

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .merge:
      return String(localized: "Merge")
    case .squash:
      return String(localized: "Squash")
    case .rebase:
      return String(localized: "Rebase")
    }
  }

  public var ghArgument: String {
    rawValue
  }
}
