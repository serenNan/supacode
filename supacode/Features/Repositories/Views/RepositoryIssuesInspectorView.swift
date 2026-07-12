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
          Image(systemName: issue.isClosed ? "checkmark.circle" : "smallcircle.filled.circle")
            .foregroundStyle(.secondary)
            .help(issue.isClosed ? "Closed" : "Open")
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
            Text(label.name)
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(.quaternary, in: .capsule)
              .foregroundStyle(.secondary)
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
