import ComposableArchitecture
import ConcurrencyExtras
import Foundation
import IdentifiedCollections
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct RepositoriesFeatureGitHistoryTests {
  private nonisolated static let hash1 = String(repeating: "a", count: 40)
  private nonisolated static let hash2 = String(repeating: "b", count: 40)

  private func makeCommit(hash: String, subject: String) -> GitCommitSummary {
    GitCommitSummary(
      hash: hash,
      shortHash: String(hash.prefix(7)),
      author: "Alice",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      refs: [],
      subject: subject
    )
  }

  private func makeSnapshot(subject: String = "feat: one") -> GitHistorySnapshot {
    GitHistorySnapshot(
      commits: [makeCommit(hash: Self.hash1, subject: subject)],
      upstreamRef: "origin/main",
      aheadCount: 1,
      isTruncated: false
    )
  }

  private func makeDetail(hash: String) -> GitCommitDetail {
    GitCommitDetail(
      hash: hash,
      author: "Alice",
      email: "alice@example.com",
      date: Date(timeIntervalSince1970: 1_700_000_000),
      message: "feat: one\n\nbody",
      files: [GitCommitFileChange(path: "README.md", added: 1, removed: 2)]
    )
  }

  private func makeWorktree(id: String, name: String, repoRoot: String = "/tmp/repo") -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot),
      createdAt: nil
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

  private func makeState(
    repositories: [Repository],
    selection: SidebarSelection? = nil
  ) -> RepositoriesFeature.State {
    var state = RepositoriesFeature.State()
    state.repositories = IdentifiedArray(uniqueElements: repositories)
    state.repositoryRoots = repositories.map(\.rootURL)
    state.selection = selection
    return state
  }

  @Test func openingHistoryPaneLoadsSelectedWorktreeHistory() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let snapshot = makeSnapshot()
    let store = TestStore(
      initialState: makeState(repositories: [repository], selection: .worktree(worktree.id))
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitHistory = { _, _ in snapshot }
    }

    await store.send(.toggleInspectorPane(.history)) {
      $0.inspectorPane = .history
      $0.inspectorPresented = true
      $0.gitHistory = RepositoriesFeature.GitHistoryState(
        worktreeID: worktree.id, isLoading: true)
    }
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = snapshot
    }
  }

  @Test func hiddenPaneIgnoresWatcherEvents() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let historyCalls = LockIsolated(0)
    let store = TestStore(
      initialState: makeState(repositories: [repository], selection: .worktree(worktree.id))
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.lineChanges = { _ in nil }
      $0.gitClient.commitHistory = { _, _ in
        historyCalls.withValue { $0 += 1 }
        return GitHistorySnapshot(commits: [], upstreamRef: nil, aheadCount: 0, isTruncated: false)
      }
    }

    await store.send(.worktreeInfoEvent(.filesChanged(worktreeID: worktree.id)))

    #expect(historyCalls.value == 0)
  }

  @Test func watcherEventsRefreshVisibleHistory() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let refreshed = makeSnapshot(subject: "feat: refreshed")
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.lineChanges = { _ in nil }
      $0.gitClient.commitHistory = { _, _ in refreshed }
    }

    await store.send(.worktreeInfoEvent(.filesChanged(worktreeID: worktree.id))) {
      $0.gitHistory?.isLoading = true
    }
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = refreshed
    }
  }

  @Test func selectionChangeReloadsHistoryForNewWorktree() async {
    let wt1 = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let wt2 = makeWorktree(id: "/tmp/repo/wt2", name: "wt2")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [wt1, wt2])
    let snapshot2 = makeSnapshot(subject: "feat: wt2")
    var initialState = makeState(repositories: [repository], selection: .worktree(wt1.id))
    initialState.sidebarSelectedWorktreeIDs = [wt1.id]
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: wt1.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitHistory = { url, _ in
        guard url.path(percentEncoded: false).hasSuffix("wt2") else {
          throw GitClientError.commandFailed(command: "git log", message: "unexpected worktree")
        }
        return snapshot2
      }
    }

    await store.send(.selectionChanged([.worktree(wt2.id)])) {
      $0.selection = .worktree(wt2.id)
      $0.sidebarSelectedWorktreeIDs = [wt2.id]
      $0.worktreeHistoryBackStack = [wt1.id]
      $0.gitHistory = RepositoriesFeature.GitHistoryState(worktreeID: wt2.id, isLoading: true)
    }
    await store.receive(\.delegate.selectedWorktreeChanged)
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = snapshot2
    }
  }

  @Test func loadFailureShowsErrorAndRetryRecovers() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let snapshot = makeSnapshot()
    let error = GitClientError.commandFailed(command: "git log", message: "boom")
    let shouldFail = LockIsolated(true)
    let store = TestStore(
      initialState: makeState(repositories: [repository], selection: .worktree(worktree.id))
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitHistory = { _, _ in
        if shouldFail.value { throw error }
        return snapshot
      }
    }

    await store.send(.toggleInspectorPane(.history)) {
      $0.inspectorPane = .history
      $0.inspectorPresented = true
      $0.gitHistory = RepositoriesFeature.GitHistoryState(
        worktreeID: worktree.id, isLoading: true)
    }
    await store.receive(\.gitHistory.failed) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.loadError = error.localizedDescription
    }

    shouldFail.setValue(false)
    await store.send(.gitHistory(.refresh)) {
      $0.gitHistory?.isLoading = true
      $0.gitHistory?.loadError = nil
    }
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = snapshot
    }
  }

  @Test func commitTapExpandsLoadsDetailAndCollapses() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var snapshot = makeSnapshot()
    snapshot = GitHistorySnapshot(
      commits: [
        makeCommit(hash: Self.hash1, subject: "feat: one"),
        makeCommit(hash: Self.hash2, subject: "fix: two"),
      ],
      upstreamRef: snapshot.upstreamRef,
      aheadCount: snapshot.aheadCount,
      isTruncated: false
    )
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: snapshot)
    let detail1 = makeDetail(hash: Self.hash1)
    let detail2 = makeDetail(hash: Self.hash2)
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitDetail = { _, hash in
        hash == Self.hash1 ? detail1 : detail2
      }
    }

    await store.send(.gitHistory(.commitTapped(hash: Self.hash1))) {
      $0.gitHistory?.expandedCommitHash = Self.hash1
    }
    await store.receive(\.gitHistory.detailLoaded) {
      $0.gitHistory?.expandedDetail = detail1
    }

    // Tapping another row swaps the expansion and reloads lazily.
    await store.send(.gitHistory(.commitTapped(hash: Self.hash2))) {
      $0.gitHistory?.expandedCommitHash = Self.hash2
      $0.gitHistory?.expandedDetail = nil
    }
    await store.receive(\.gitHistory.detailLoaded) {
      $0.gitHistory?.expandedDetail = detail2
    }

    // Tapping the expanded row collapses it.
    await store.send(.gitHistory(.commitTapped(hash: Self.hash2))) {
      $0.gitHistory?.expandedCommitHash = nil
      $0.gitHistory?.expandedDetail = nil
    }
  }

  @Test func openingHistoryPaneSeedsUncommittedCountsFromSidebarRow() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let snapshot = makeSnapshot()
    var row = SidebarItemFeature.State(
      id: worktree.id,
      repositoryID: repository.id,
      kind: .gitWorktree,
      name: worktree.name,
      branchName: worktree.name,
      subtitle: nil,
      workingDirectory: worktree.workingDirectory,
      repositoryAccent: nil,
      isMainWorktree: false,
      isPinned: false,
      hasMergedBadge: false
    )
    row.addedLines = 12
    row.removedLines = 3
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.sidebarItems = [row]
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitHistory = { _, _ in snapshot }
    }

    await store.send(.toggleInspectorPane(.history)) {
      $0.inspectorPane = .history
      $0.inspectorPresented = true
      var history = RepositoriesFeature.GitHistoryState(worktreeID: worktree.id, isLoading: true)
      history.uncommittedAdded = 12
      history.uncommittedRemoved = 3
      $0.gitHistory = history
    }
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = snapshot
    }
  }

  @Test func diffStatsChangeSyncsVisibleHistoryUncommittedCounts() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let row = SidebarItemFeature.State(
      id: worktree.id,
      repositoryID: repository.id,
      kind: .gitWorktree,
      name: worktree.name,
      branchName: worktree.name,
      subtitle: nil,
      workingDirectory: worktree.workingDirectory,
      repositoryAccent: nil,
      isMainWorktree: false,
      isPinned: false,
      hasMergedBadge: false
    )
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.sidebarItems = [row]
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }

    await store.send(
      .sidebarItems(.element(id: worktree.id, action: .diffStatsChanged(added: 5, removed: 1)))
    ) {
      $0.sidebarItems[id: worktree.id]?.addedLines = 5
      $0.sidebarItems[id: worktree.id]?.removedLines = 1
      $0.gitHistory?.uncommittedAdded = 5
      $0.gitHistory?.uncommittedRemoved = 1
    }
  }

  @Test func uncommittedTapExpandsLoadsFilesAndCollapses() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let files = [GitCommitFileChange(path: "README.md", added: 5, removed: 1)]
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.uncommittedFiles = { _ in files }
    }

    await store.send(.gitHistory(.uncommittedTapped)) {
      $0.gitHistory?.isUncommittedExpanded = true
    }
    await store.receive(\.gitHistory.uncommittedFilesLoaded) {
      $0.gitHistory?.uncommittedFiles = files
    }
    await store.send(.gitHistory(.uncommittedTapped)) {
      $0.gitHistory?.isUncommittedExpanded = false
      $0.gitHistory?.uncommittedFiles = nil
    }
  }

  @Test func expandingCommitCollapsesUncommittedAndViceVersa() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let files = [GitCommitFileChange(path: "README.md", added: 5, removed: 1)]
    let detail = makeDetail(hash: Self.hash1)
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.uncommittedFiles = { _ in files }
      $0.gitClient.commitDetail = { _, _ in detail }
    }

    await store.send(.gitHistory(.uncommittedTapped)) {
      $0.gitHistory?.isUncommittedExpanded = true
    }
    await store.receive(\.gitHistory.uncommittedFilesLoaded) {
      $0.gitHistory?.uncommittedFiles = files
    }

    // Expanding a commit closes the uncommitted node.
    await store.send(.gitHistory(.commitTapped(hash: Self.hash1))) {
      $0.gitHistory?.expandedCommitHash = Self.hash1
      $0.gitHistory?.isUncommittedExpanded = false
      $0.gitHistory?.uncommittedFiles = nil
    }
    await store.receive(\.gitHistory.detailLoaded) {
      $0.gitHistory?.expandedDetail = detail
    }

    // Expanding the uncommitted node closes the commit.
    await store.send(.gitHistory(.uncommittedTapped)) {
      $0.gitHistory?.isUncommittedExpanded = true
      $0.gitHistory?.expandedCommitHash = nil
      $0.gitHistory?.expandedDetail = nil
    }
    await store.receive(\.gitHistory.uncommittedFilesLoaded) {
      $0.gitHistory?.uncommittedFiles = files
    }
  }

  @Test func watcherRefreshReloadsExpandedUncommittedFiles() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let refreshedFiles = [GitCommitFileChange(path: "New.swift", added: 9, removed: 0)]
    let refreshed = makeSnapshot(subject: "feat: refreshed")
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    var history = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    history.isUncommittedExpanded = true
    history.uncommittedFiles = [GitCommitFileChange(path: "Old.swift", added: 1, removed: 1)]
    initialState.gitHistory = history
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.lineChanges = { _ in nil }
      $0.gitClient.commitHistory = { _, _ in refreshed }
      $0.gitClient.uncommittedFiles = { _ in refreshedFiles }
    }

    await store.send(.worktreeInfoEvent(.filesChanged(worktreeID: worktree.id))) {
      $0.gitHistory?.isLoading = true
    }
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = refreshed
    }
    await store.receive(\.gitHistory.uncommittedFilesLoaded) {
      $0.gitHistory?.uncommittedFiles = refreshedFiles
    }
  }

  @Test func closingInspectorClearsHistory() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }

    await store.send(.toggleInspectorPane(.history)) {
      $0.inspectorPresented = false
      $0.gitHistory = nil
    }
  }

  private func makeFileDiff() -> GitFileDiff {
    GitFileDiff(
      hunks: [
        GitDiffHunk(
          header: "@@ -1 +1 @@",
          lines: [GitDiffLine(kind: .added, text: "new", oldNumber: nil, newNumber: 1)]
        )
      ],
      isBinary: false
    )
  }

  private func makeHistoryVisibleState(worktree: Worktree, repository: Repository)
    -> RepositoriesFeature.State
  {
    var state = makeState(repositories: [repository], selection: .worktree(worktree.id))
    state.inspectorPane = .history
    state.inspectorPresented = true
    state.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    return state
  }

  @Test func fileTapPresentsAndLoadsUncommittedDiff() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let diff = makeFileDiff()
    let requestedPath = LockIsolated("")
    let store = TestStore(
      initialState: makeHistoryVisibleState(worktree: worktree, repository: repository)
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.uncommittedFileDiff = { _, path in
        requestedPath.setValue(path)
        return diff
      }
    }

    await store.send(.gitHistory(.fileTapped(source: .uncommitted, path: "supacode/A.swift"))) {
      $0.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
        source: .uncommitted, filePath: "supacode/A.swift")
    }
    await store.receive(\.gitHistory.fileDiffLoaded) {
      $0.gitHistory?.presentedDiff?.diff = diff
    }
    #expect(requestedPath.value == "supacode/A.swift")
  }

  @Test func fileTapInCommitLoadsCommitDiff() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let diff = makeFileDiff()
    let requestedHash = LockIsolated("")
    let store = TestStore(
      initialState: makeHistoryVisibleState(worktree: worktree, repository: repository)
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitFileDiff = { _, hash, _ in
        requestedHash.setValue(hash)
        return diff
      }
    }

    await store.send(
      .gitHistory(.fileTapped(source: .commit(hash: Self.hash1), path: "README.md"))
    ) {
      $0.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
        source: .commit(hash: Self.hash1), filePath: "README.md")
    }
    await store.receive(\.gitHistory.fileDiffLoaded) {
      $0.gitHistory?.presentedDiff?.diff = diff
    }
    #expect(requestedHash.value == Self.hash1)
  }

  @Test func fileDiffFailureShowsError() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let store = TestStore(
      initialState: makeHistoryVisibleState(worktree: worktree, repository: repository)
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.uncommittedFileDiff = { _, _ in
        throw GitClientError.commandFailed(command: "git diff", message: "boom")
      }
    }

    await store.send(.gitHistory(.fileTapped(source: .uncommitted, path: "A.swift"))) {
      $0.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
        source: .uncommitted, filePath: "A.swift")
    }
    await store.receive(\.gitHistory.fileDiffFailed) {
      $0.gitHistory?.presentedDiff?.error = GitClientError.commandFailed(
        command: "git diff", message: "boom"
      ).localizedDescription
    }
  }

  @Test func staleFileDiffResponsesAreIgnored() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initialState = makeHistoryVisibleState(worktree: worktree, repository: repository)
    initialState.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
      source: .uncommitted, filePath: "Current.swift")
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }

    await store.send(
      .gitHistory(
        .fileDiffLoaded(
          worktreeID: worktree.id, source: .uncommitted, path: "Other.swift", makeFileDiff()))
    )
    await store.send(
      .gitHistory(
        .fileDiffFailed(
          worktreeID: WorktreeID("/tmp/repo/wt2"), source: .uncommitted, path: "Current.swift",
          message: "boom"))
    )
  }

  @Test func diffDismissedClearsPresentedDiff() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initialState = makeHistoryVisibleState(worktree: worktree, repository: repository)
    initialState.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
      source: .uncommitted, filePath: "A.swift", diff: makeFileDiff())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }

    await store.send(.gitHistory(.diffDismissed)) {
      $0.gitHistory?.presentedDiff = nil
    }
  }

  @Test func closingInspectorDismissesPresentedDiff() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    var initialState = makeHistoryVisibleState(worktree: worktree, repository: repository)
    initialState.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
      source: .uncommitted, filePath: "A.swift", diff: makeFileDiff())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }

    await store.send(.toggleInspectorPane(.history)) {
      $0.inspectorPresented = false
      $0.gitHistory = nil
    }
  }
}
