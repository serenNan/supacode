import ComposableArchitecture
import SupacodeSettingsShared
import SwiftUI

/// Which issues the inspector lists: all open repository issues, or only the
/// ones the signed-in user is involved in.
enum IssueScope: String, CaseIterable, Identifiable {
  case all = "All"
  case mine = "Mine"
  var id: Self { self }
}

/// Secondary open/closed filter, applied only within the Mine scope (the Mine
/// set carries closed issues; the All set is open-only).
enum IssueStateFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case open = "Open"
  case closed = "Closed"
  var id: Self { self }
}

/// Inspector section listing the repository's GitHub issues. Reads the issue
/// state in its own body so issue churn invalidates only this pane.
struct RepositoryIssuesInspectorView: View {
  let repositoryID: Repository.ID?
  let repositoriesStore: StoreOf<RepositoriesFeature>
  @State private var scope: IssueScope = .all
  @State private var stateFilter: IssueStateFilter = .all

  var body: some View {
    if let repositoryID, let allIssues = repositoriesStore.issuesByRepositoryID[repositoryID] {
      IssuesPane(
        scope: $scope,
        stateFilter: $stateFilter,
        allIssues: allIssues,
        involvedIssues: repositoriesStore.involvedIssuesByRepositoryID[repositoryID] ?? []
      )
    } else if repositoriesStore.githubIntegrationAvailability == .available {
      VStack(spacing: 10) {
        ProgressView()
        Text("Checking for issues…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ContentUnavailableView(
        "Issues Unavailable",
        systemImage: "exclamationmark.circle",
        description: Text("Issues need the GitHub integration (`gh` CLI) to be available and enabled.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

private struct IssuesPane: View {
  @Binding var scope: IssueScope
  @Binding var stateFilter: IssueStateFilter
  let allIssues: [GithubIssue]
  let involvedIssues: [GithubIssue]

  private var displayedIssues: [GithubIssue] {
    switch scope {
    case .all:
      return allIssues
    case .mine:
      switch stateFilter {
      case .all: return involvedIssues
      case .open: return involvedIssues.filter { !$0.isClosed }
      case .closed: return involvedIssues.filter(\.isClosed)
      }
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      filters
      if displayedIssues.isEmpty {
        emptyState
      } else {
        IssuesListContent(issues: displayedIssues, scope: scope)
      }
    }
  }

  private var filters: some View {
    VStack(spacing: 8) {
      Picker("Issue scope", selection: $scope) {
        ForEach(IssueScope.allCases) { scope in
          Text(scope.rawValue).tag(scope)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .help("Show all open issues, or only the issues you're involved in.")

      if scope == .mine {
        Picker("Issue state", selection: $stateFilter) {
          ForEach(IssueStateFilter.allCases) { state in
            Text(state.rawValue).tag(state)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Filter your issues by open or closed state.")
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  private var emptyState: some View {
    ContentUnavailableView(
      scope == .all ? "No Open Issues" : "No Issues Involve You",
      systemImage: "checkmark.circle",
      description: Text(
        scope == .all
          ? "This repository has no open issues."
          : "No issues match this filter that you authored, were assigned, mentioned in, or commented on."
      )
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct IssuesListContent: View {
  let issues: [GithubIssue]
  let scope: IssueScope

  var body: some View {
    // One clock for every relative timestamp, ticking each minute.
    TimelineView(.everyMinute) { context in
      Form {
        Section {
          ForEach(issues) { issue in
            IssueRow(issue: issue, now: context.date)
          }
        } header: {
          Text(headerLabel)
            .textCase(nil)
        }
      }
      .formStyle(.grouped)
      // Let the window's terminal background (set in WindowChromeApplier) show through.
      .scrollContentBackground(.hidden)
    }
  }

  private var headerLabel: String {
    let noun = issues.count == 1 ? "issue" : "issues"
    // The All scope is open-only; the Mine scope can mix open and closed.
    return scope == .all ? "\(issues.count) open \(noun)" : "\(issues.count) \(noun)"
  }
}

private struct IssueRow: View {
  let issue: GithubIssue
  let now: Date
  @Environment(\.openURL) private var openURL
  @Environment(\.analyticsClient) private var analyticsClient

  var body: some View {
    Button {
      if let url = URL(string: issue.url) {
        analyticsClient.capture("github_issue_opened", nil)
        openURL(url)
      }
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          IssueStatusIcon(issue: issue)
          Text(verbatim: "#\(issue.number)")
            .foregroundStyle(.secondary)
            .monospaced()
          Text(issue.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
          Spacer(minLength: 6)
          if let updatedAt = issue.updatedAt {
            Text(Self.relativeTime(updatedAt, now: now))
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
        }
        HStack(spacing: 6) {
          if let authorLogin = issue.authorLogin {
            Text(authorLogin)
              .foregroundStyle(.secondary)
          }
          ForEach(issue.labels, id: \.name) { label in
            GithubLabelChip(label: label)
          }
          Spacer(minLength: 0)
          if issue.commentsCount > 0 {
            Label("\(issue.commentsCount)", systemImage: "bubble.left")
              .foregroundStyle(.secondary)
              .labelStyle(.titleAndIcon)
          }
        }
        .font(.caption)
        .lineLimit(1)
      }
      .contentShape(.rect)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .help("Open issue on GitHub.")
  }

  private static func relativeTime(_ date: Date, now: Date) -> String {
    guard now.timeIntervalSince(date) >= 60 else { return "now" }
    return date.formatted(.relative(presentation: .named, unitsStyle: .narrow))
  }
}

/// GitHub's issue status glyph: green dot for open, purple check for
/// closed-completed, gray slash for closed-not-planned. SF Symbols approximate
/// GitHub's octicons; the colors match GitHub's status semantics.
private struct IssueStatusIcon: View {
  let issue: GithubIssue

  var body: some View {
    Image(systemName: descriptor.symbol)
      .foregroundStyle(descriptor.tint)
      .help(descriptor.label)
  }

  private var descriptor: (symbol: String, tint: AnyShapeStyle, label: String) {
    guard issue.isClosed else {
      return ("smallcircle.filled.circle", AnyShapeStyle(.green), "Open")
    }
    if issue.stateReason == "NOT_PLANNED" {
      return ("circle.slash", AnyShapeStyle(.secondary), "Closed as not planned")
    }
    return ("checkmark.circle.fill", AnyShapeStyle(.purple), "Closed as completed")
  }
}

/// A GitHub label rendered like github.com: in dark mode a translucent tint of
/// the label's own color with lightened text and a subtle same-color border; in
/// light mode a solid fill with contrast text. The hex is API data, not app
/// chrome, so it's exempt from the "system colors only" rule. Falls back to a
/// neutral chip when the hex is missing or malformed.
private struct GithubLabelChip: View {
  let label: GithubIssueLabel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let style = GithubLabelStyle.resolve(hex: label.color, dark: colorScheme == .dark)
    Text(label.name)
      .padding(.horizontal, 7)
      .padding(.vertical, 1)
      .foregroundStyle(style?.text ?? AnyShapeStyle(.secondary))
      .background(style?.background ?? AnyShapeStyle(.quaternary), in: .capsule)
      .overlay(
        Capsule().strokeBorder(style?.border ?? Color.clear, lineWidth: style == nil ? 0 : 1)
      )
  }
}

/// Resolves GitHub Primer's label colors from a hex color, per color scheme.
enum GithubLabelStyle {
  struct Resolved {
    let background: AnyShapeStyle
    let text: AnyShapeStyle
    let border: Color
  }

  static func resolve(hex: String, dark: Bool) -> Resolved? {
    let trimmed = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
      return nil
    }
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    // GitHub's perceived lightness: Rec. 709 luma of the raw channels.
    let perceived = 0.2126 * red + 0.7152 * green + 0.0722 * blue
    let (hue, saturation, lightness) = Self.hsl(red: red, green: green, blue: blue)

    if dark {
      let lightenBy = perceived < 0.6 ? (0.6 - perceived) * 100 : 0
      let textColor = Self.color(hue: hue, saturation: saturation, lightness: min(100, lightness + lightenBy))
      return Resolved(
        background: AnyShapeStyle(Color(.sRGB, red: red, green: green, blue: blue, opacity: 0.18)),
        text: AnyShapeStyle(textColor),
        border: textColor.opacity(0.3)
      )
    }
    let text: Color = perceived < 0.453 ? .white : .black
    // Only near-white labels need a border in light mode so they don't vanish.
    let border: Color =
      perceived > 0.9
      ? Self.color(hue: hue, saturation: saturation, lightness: max(0, lightness - 25)) : .clear
    return Resolved(
      background: AnyShapeStyle(Color(.sRGB, red: red, green: green, blue: blue)),
      text: AnyShapeStyle(text),
      border: border
    )
  }

  // sRGB (0...1) -> HSL with hue in degrees, saturation and lightness in percent.
  private static func hsl(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
    let maxV = max(red, green, blue)
    let minV = min(red, green, blue)
    let lightness = (maxV + minV) / 2
    guard maxV != minV else { return (0, 0, lightness * 100) }
    let delta = maxV - minV
    let saturation = lightness > 0.5 ? delta / (2 - maxV - minV) : delta / (maxV + minV)
    let hue: Double
    switch maxV {
    case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
    case green: hue = (blue - red) / delta + 2
    default: hue = (red - green) / delta + 4
    }
    return (hue / 6 * 360, saturation * 100, lightness * 100)
  }

  // HSL (hue deg, saturation%, lightness%) -> SwiftUI Color.
  private static func color(hue: Double, saturation: Double, lightness: Double) -> Color {
    let hueFraction = hue / 360
    let sat = saturation / 100
    let lum = lightness / 100
    guard sat != 0 else { return Color(.sRGB, red: lum, green: lum, blue: lum) }
    let q = lum < 0.5 ? lum * (1 + sat) : lum + sat - lum * sat
    let p = 2 * lum - q
    return Color(
      .sRGB,
      red: Self.channel(p, q, hueFraction + 1.0 / 3),
      green: Self.channel(p, q, hueFraction),
      blue: Self.channel(p, q, hueFraction - 1.0 / 3)
    )
  }

  private static func channel(_ p: Double, _ q: Double, _ t0: Double) -> Double {
    var t = t0
    if t < 0 { t += 1 }
    if t > 1 { t -= 1 }
    if t < 1.0 / 6 { return p + (q - p) * 6 * t }
    if t < 1.0 / 2 { return q }
    if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
    return p
  }
}
