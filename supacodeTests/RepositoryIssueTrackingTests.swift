import ComposableArchitecture
import Foundation
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct RepositoryIssueTrackingTests {
  // MARK: - Snapshot diffing (pure)

  @Test func firstLoadSeedsWithoutNotifications() {
    let updates = RepositoryIssueUpdates.notifications(
      repositoryID: "/tmp/repo",
      previous: nil,
      issues: [makeIssue(number: 1, commentsCount: 5)],
      uuid: { UUID() },
      now: Date(timeIntervalSince1970: 0)
    )
    #expect(updates.isEmpty)
  }

  @Test func commentCountIncreaseNotifies() {
    let previous = RepositoryIssueUpdates.snapshot(of: [makeIssue(number: 630, commentsCount: 2)])
    let updates = RepositoryIssueUpdates.notifications(
      repositoryID: "/tmp/repo",
      previous: previous,
      issues: [makeIssue(number: 630, title: "Clamp body", commentsCount: 3)],
      uuid: { UUID() },
      now: Date(timeIntervalSince1970: 0)
    )
    #expect(updates.count == 1)
    #expect(updates.first?.title == "New comment on #630")
    #expect(updates.first?.body == "Clamp body")
    #expect(updates.first?.issueNumber == 630)
  }

  @Test func labelChangeNotifiesWithDelta() {
    let previous = RepositoryIssueUpdates.snapshot(of: [
      makeIssue(number: 630, labels: [GithubIssueLabel(name: "enhancement", color: "a2eeef")])
    ])
    let updates = RepositoryIssueUpdates.notifications(
      repositoryID: "/tmp/repo",
      previous: previous,
      issues: [
        makeIssue(
          number: 630,
          labels: [
            GithubIssueLabel(name: "enhancement", color: "a2eeef"),
            GithubIssueLabel(name: "ready", color: "0e8a16"),
          ]
        )
      ],
      uuid: { UUID() },
      now: Date(timeIntervalSince1970: 0)
    )
    #expect(updates.count == 1)
    #expect(updates.first?.title == "Labels changed on #630 (+ready)")
  }

  @Test func newIssueNotifies() {
    let previous = RepositoryIssueUpdates.snapshot(of: [makeIssue(number: 1)])
    let updates = RepositoryIssueUpdates.notifications(
      repositoryID: "/tmp/repo",
      previous: previous,
      issues: [makeIssue(number: 1), makeIssue(number: 2, title: "Fresh bug")],
      uuid: { UUID() },
      now: Date(timeIntervalSince1970: 0)
    )
    #expect(updates.count == 1)
    #expect(updates.first?.title == "New issue #2")
    #expect(updates.first?.body == "Fresh bug")
  }

  @Test func unchangedIssuesProduceNothing() {
    let issues = [makeIssue(number: 1, commentsCount: 4)]
    let updates = RepositoryIssueUpdates.notifications(
      repositoryID: "/tmp/repo",
      previous: RepositoryIssueUpdates.snapshot(of: issues),
      issues: issues,
      uuid: { UUID() },
      now: Date(timeIntervalSince1970: 0)
    )
    #expect(updates.isEmpty)
  }

  // MARK: - Reducer integration

  @Test func issueRefreshFetchesAndStoresIssues() async {
    let repoRoot = "/tmp/repo"
    let worktree = makeWorktree(id: repoRoot, name: "main", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [worktree])
    var state = makeState(repositories: [repository])
    state.githubIntegrationAvailability = .available
    let issue = makeIssue(number: 630, title: "Clamp body", commentsCount: 2)
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }
    store.dependencies.githubCLI.resolveRemoteInfo = { _ in
      GithubRemoteInfo(host: "github.com", owner: "octo", repo: "repo")
    }
    store.dependencies.githubCLI.listIssues = { _, _, _ in [issue] }

    await store.send(
      .worktreeInfoEvent(.repositoryIssueRefresh(repositoryRootURL: repository.rootURL))
    ) {
      $0.inFlightIssueRefreshRepositoryIDs = [repository.id]
    }
    await store.receive(\.repositoryIssuesLoaded) {
      $0.issuesByRepositoryID[repository.id] = [issue]
      $0.issueSnapshotsByRepositoryID[repository.id] = RepositoryIssueUpdates.snapshot(of: [issue])
    }
    await store.receive(\.repositoryIssueRefreshCompleted) {
      $0.inFlightIssueRefreshRepositoryIDs = []
    }
    #expect(store.state.issueNotifications.isEmpty)
  }

  @Test func secondLoadWithNewCommentAppendsNotification() async {
    let repoRoot = "/tmp/repo"
    let worktree = makeWorktree(id: repoRoot, name: "main", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [worktree])
    var state = makeState(repositories: [repository])
    state.githubIntegrationAvailability = .available
    let seeded = makeIssue(number: 630, title: "Clamp body", commentsCount: 2)
    state.issuesByRepositoryID[repository.id] = [seeded]
    state.issueSnapshotsByRepositoryID[repository.id] = RepositoryIssueUpdates.snapshot(of: [seeded])
    let updated = makeIssue(number: 630, title: "Clamp body", commentsCount: 3)
    let fixedDate = Date(timeIntervalSince1970: 1_000_000)
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }
    store.dependencies.uuid = .incrementing
    store.dependencies.date = .constant(fixedDate)
    store.dependencies.sidebarStructureAutoRecompute = false

    await store.send(
      .repositoryIssuesLoaded(repositoryID: repository.id, issues: [updated])
    ) {
      $0.issuesByRepositoryID[repository.id] = [updated]
      $0.issueSnapshotsByRepositoryID[repository.id] = RepositoryIssueUpdates.snapshot(of: [updated])
      $0.issueNotifications = [
        RepositoryIssueNotification(
          id: UUID(0),
          repositoryID: repository.id,
          issueNumber: 630,
          title: "New comment on #630",
          body: "Clamp body",
          url: updated.url,
          createdAt: fixedDate
        )
      ]
    }
  }

  @Test func issueRefreshDoesNothingWhenIntegrationDisabled() async {
    let repoRoot = "/tmp/repo"
    let worktree = makeWorktree(id: repoRoot, name: "main", repoRoot: repoRoot)
    let repository = makeRepository(id: repoRoot, worktrees: [worktree])
    var state = makeState(repositories: [repository])
    state.githubIntegrationAvailability = .disabled
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(
      .worktreeInfoEvent(.repositoryIssueRefresh(repositoryRootURL: repository.rootURL))
    )
  }

  @Test func issueRefreshSkipsUnknownRepository() async {
    let store = TestStore(initialState: RepositoriesFeature.State()) {
      RepositoriesFeature()
    }

    await store.send(
      .worktreeInfoEvent(
        .repositoryIssueRefresh(repositoryRootURL: URL(fileURLWithPath: "/tmp/ghost"))
      )
    )
  }

  @Test func repositoriesLoadedPrunesIssueStateOfRemovedRepositories() async {
    let keptRoot = "/tmp/kept"
    let removedRoot = "/tmp/removed"
    let kept = makeRepository(
      id: keptRoot,
      worktrees: [makeWorktree(id: keptRoot, name: "main", repoRoot: keptRoot)]
    )
    let removed = makeRepository(
      id: removedRoot,
      worktrees: [makeWorktree(id: removedRoot, name: "main", repoRoot: removedRoot)]
    )
    var state = makeState(repositories: [kept, removed])
    let issue = makeIssue(number: 1)
    state.issuesByRepositoryID = [kept.id: [issue], removed.id: [issue]]
    state.issueSnapshotsByRepositoryID = [
      kept.id: RepositoryIssueUpdates.snapshot(of: [issue]),
      removed.id: RepositoryIssueUpdates.snapshot(of: [issue]),
    ]
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }
    store.exhaustivity = .off

    await store.send(.repositoriesLoaded([kept], failures: [], roots: [kept.rootURL], animated: false))

    #expect(store.state.issuesByRepositoryID[removed.id] == nil)
    #expect(store.state.issueSnapshotsByRepositoryID[removed.id] == nil)
    #expect(store.state.issuesByRepositoryID[kept.id] == [issue])
  }

  @Test func selectingIssueNotificationMarksItRead() async {
    let repoRoot = "/tmp/repo"
    let repository = makeRepository(
      id: repoRoot,
      worktrees: [makeWorktree(id: repoRoot, name: "main", repoRoot: repoRoot)]
    )
    var state = makeState(repositories: [repository])
    let notification = RepositoryIssueNotification(
      id: UUID(0),
      repositoryID: repository.id,
      issueNumber: 630,
      title: "New comment on #630",
      body: "Clamp body",
      url: "https://github.com/octo/repo/issues/630",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    state.issueNotifications = [notification]
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }
    store.dependencies.sidebarStructureAutoRecompute = false

    await store.send(.issueNotificationSelected(notification.id)) {
      $0.issueNotifications[id: notification.id]?.isRead = true
    }
  }

  @Test func dismissAllIssueNotificationsClearsThem() async {
    let repoRoot = "/tmp/repo"
    let repository = makeRepository(
      id: repoRoot,
      worktrees: [makeWorktree(id: repoRoot, name: "main", repoRoot: repoRoot)]
    )
    var state = makeState(repositories: [repository])
    state.issueNotifications = [
      RepositoryIssueNotification(
        id: UUID(0),
        repositoryID: repository.id,
        issueNumber: 1,
        title: "New issue #1",
        body: "Issue",
        url: "https://github.com/octo/repo/issues/1",
        createdAt: Date(timeIntervalSince1970: 0)
      )
    ]
    let store = TestStore(initialState: state) {
      RepositoriesFeature()
    }

    await store.send(.dismissAllIssueNotifications) {
      $0.issueNotifications = []
    }
  }

  // MARK: - Helpers

  private func makeIssue(
    number: Int,
    title: String = "Issue",
    labels: [GithubIssueLabel] = [],
    commentsCount: Int = 0
  ) -> GithubIssue {
    GithubIssue(
      number: number,
      title: title,
      url: "https://github.com/octo/repo/issues/\(number)",
      updatedAt: nil,
      authorLogin: "octocat",
      labels: labels,
      commentsCount: commentsCount
    )
  }

  private func makeWorktree(id: String, name: String, repoRoot: String) -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
  }

  private func makeRepository(id: String, worktrees: [Worktree]) -> Repository {
    Repository(
      id: RepositoryID(id),
      rootURL: URL(fileURLWithPath: id),
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }

  private func makeState(repositories: [Repository]) -> RepositoriesFeature.State {
    var state = RepositoriesFeature.State()
    state.repositories = IdentifiedArray(uniqueElements: repositories)
    state.repositoryRoots = repositories.map(\.rootURL)
    return state
  }
}
