import Foundation

/// Identifies the semantic category of a user-defined script.
/// Predefined kinds carry default icon, color, and name; `.custom`
/// requires explicit values stored on the owning `ScriptDefinition`.
public enum ScriptKind: String, Codable, CaseIterable, Hashable, Sendable {
  case run
  case test
  case deploy
  case lint
  case format
  case custom

  /// Default display name shown in UI when the user hasn't provided one.
  public nonisolated var defaultName: String {
    switch self {
    case .run: String(localized: "Run")
    case .test: String(localized: "Test")
    case .deploy: String(localized: "Deploy")
    case .lint: String(localized: "Lint")
    case .format: String(localized: "Format")
    case .custom: String(localized: "Custom")
    }
  }

  /// Default SF Symbol name for the script kind.
  public nonisolated var defaultSystemImage: String {
    switch self {
    case .run: "play"
    case .test: "play.diamond"
    case .deploy: "arrowshape.turn.up.forward"
    case .lint: "exclamationmark.triangle"
    case .format: "circle.dotted.circle"
    case .custom: "text.alignleft"
    }
  }

  /// Default tint color for the script kind.
  public nonisolated var defaultTintColor: RepositoryColor {
    switch self {
    case .run: .green
    case .test: .yellow
    case .deploy: .red
    case .lint: .blue
    case .format: .teal
    case .custom: .purple
    }
  }
}
