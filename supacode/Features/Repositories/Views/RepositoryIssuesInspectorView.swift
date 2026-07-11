import ComposableArchitecture
import SupacodeSettingsShared
import SwiftUI

/// Inspector section listing the repository's open GitHub issues. Reads the
/// issue state in its own body so issue churn invalidates only this pane.
struct RepositoryIssuesInspectorView: View {
  let repositoryID: Repository.ID?
  let repositoriesStore: StoreOf<RepositoriesFeature>

  var body: some View {
    if let repositoryID, let issues = repositoriesStore.issuesByRepositoryID[repositoryID] {
      if issues.isEmpty {
        ContentUnavailableView(
          "No Open Issues",
          systemImage: "checkmark.circle",
          description: Text("This repository has no open issues.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        IssuesListContent(issues: issues)
      }
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

private struct IssuesListContent: View {
  let issues: [GithubIssue]

  var body: some View {
    // One clock for every relative timestamp, ticking each minute.
    TimelineView(.everyMinute) { context in
      Form {
        Section {
          ForEach(issues) { issue in
            IssueRow(issue: issue, now: context.date)
          }
        } header: {
          Text("\(issues.count) open \(issues.count == 1 ? "issue" : "issues")")
            .textCase(nil)
        }
      }
      .formStyle(.grouped)
      // Let the window's terminal background (set in WindowChromeApplier) show through.
      .scrollContentBackground(.hidden)
    }
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
