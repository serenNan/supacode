import SupacodeSettingsShared
import SwiftUI

/// The visual variant an agent badge renders for a given presence activity.
/// Pure mapping so the activity → variant decision is unit-tested without a
/// SwiftUI host.
enum AgentBadgeVisual: Equatable {
  /// `busy` / `idle`: the plain agent mark on the standard badge.
  case normal
  /// Contrast-flipped badge (the agent is parked on the user).
  case awaitingInput
  /// Turn ended in an API error: red badge + template white mark.
  case errored
  /// Context compaction in progress: normal badge + a rotating ring.
  case compacting

  static func resolve(_ activity: AgentPresenceFeature.Activity) -> AgentBadgeVisual {
    switch activity {
    case .errored: .errored
    case .compacting: .compacting
    case .awaitingInput: .awaitingInput
    case .busy, .idle: .normal
    }
  }
}

/// Circular badge with the agent's mark. Its appearance is driven by the
/// agent's presence `activity` (see `AgentBadgeVisual`):
/// - `awaitingInput` inverts the subtree's colorScheme so `.bar`, `.primary`,
///   and asset variants flip together — a contrast cue that doesn't clash with
///   marks that are already orange (Claude).
/// - `errored` paints the circle red and renders the mark as a white template,
///   so a silently-broken session reads as a call to action on the badge itself
///   rather than a separate glyph beside it.
/// - `compacting` keeps the normal mark and strokes a rotating ring around it.
struct AgentBadgeView: View {
  let agent: SkillAgent
  let size: CGFloat
  let activity: AgentPresenceFeature.Activity
  @Environment(\.pixelLength) private var pixelLength
  @Environment(\.colorScheme) private var colorScheme

  init(agent: SkillAgent, size: CGFloat = 14, activity: AgentPresenceFeature.Activity = .idle) {
    self.agent = agent
    self.size = size
    self.activity = activity
  }

  var body: some View {
    // Read `activity` at body top so SwiftUI's diffing picks up the flag the moment it flips.
    let visual = AgentBadgeVisual.resolve(activity)
    let resolvedScheme: ColorScheme =
      visual == .awaitingInput
      ? (colorScheme == .dark ? .light : .dark)
      : colorScheme
    let markStyle: AnyShapeStyle =
      visual == .errored
      ? AnyShapeStyle(.white)
      : AnyShapeStyle(resolvedScheme == .dark ? .white : .black)

    Image(agent.assetName)
      // Force template on error so every agent's mark reads as a white glyph on
      // the red circle; keep original colors otherwise.
      .renderingMode(visual == .errored ? .template : .original)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .accessibilityLabel(Self.accessibilityLabel(visual, agent: agent))
      .padding(size * 0.18)
      .frame(width: size, height: size)
      .foregroundStyle(markStyle)
      .background(Self.badgeFill(visual).shadow(Self.dropShadow), in: .circle)
      .overlay(Circle().strokeBorder(.separator, lineWidth: pixelLength))
      .overlay { if visual == .compacting { CompactingRing() } }
      .environment(\.colorScheme, resolvedScheme)
      .help(Self.helpText(visual, agent: agent))
      .animation(.smooth, value: activity)
  }

  private static func badgeFill(_ visual: AgentBadgeVisual) -> AnyShapeStyle {
    visual == .errored ? AnyShapeStyle(.red) : AnyShapeStyle(.bar)
  }

  private static func helpText(_ visual: AgentBadgeVisual, agent: SkillAgent) -> String {
    switch visual {
    case .errored: "\(agent.displayName) hit an API error — needs a manual restart"
    case .compacting: "\(agent.displayName) is compacting context…"
    case .awaitingInput, .normal: agent.displayName
    }
  }

  private static func accessibilityLabel(_ visual: AgentBadgeVisual, agent: SkillAgent) -> String {
    switch visual {
    case .errored: "\(agent.displayName), error, needs manual restart"
    case .compacting: "\(agent.displayName), compacting context"
    case .awaitingInput, .normal: agent.displayName
    }
  }

  private static let dropShadow: ShadowStyle = .drop(
    color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1
  )
}

/// A rotating arc stroked around the agent badge while it compacts context.
/// Spins continuously; respects `accessibilityReduceMotion` by holding a static
/// partial ring instead. Purely decorative, so it never takes hit-testing.
private struct CompactingRing: View {
  @State private var spinning = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.3)
      .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
      .padding(-2)
      .rotationEffect(.degrees(spinning ? 360 : 0))
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
          spinning = true
        }
      }
      .allowsHitTesting(false)
  }
}
