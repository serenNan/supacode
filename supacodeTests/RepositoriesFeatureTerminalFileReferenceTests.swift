import ComposableArchitecture
import ConcurrencyExtras
import Foundation
import IdentifiedCollections
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct RepositoriesTerminalFileReferenceTests {
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

  private func makeSnapshot() -> GitHistorySnapshot {
    GitHistorySnapshot(
      commits: [],
      upstreamRef: nil,
      aheadCount: 0,
      isTruncated: false
    )
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

  @Test func referenceOpensHistoryPaneAndPresentsDiff() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let snapshot = makeSnapshot()
    let diff = makeFileDiff()
    let store = TestStore(
      initialState: makeState(repositories: [repository], selection: .worktree(worktree.id))
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitHistory = { _, _ in snapshot }
      $0.gitClient.uncommittedFileDiff = { _, _ in diff }
    }

    await store.send(
      .openTerminalFileReference(worktreeID: worktree.id, path: "supacode/A.swift", line: 42)
    ) {
      $0.inspectorPane = .history
      $0.inspectorPresented = true
      $0.gitHistory = RepositoriesFeature.GitHistoryState(
        worktreeID: worktree.id, isLoading: true)
    }
    await store.receive(\.gitHistory.fileTapped) {
      $0.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
        source: .uncommitted, filePath: "supacode/A.swift", targetLine: 42)
    }
    await store.receive(\.gitHistory.fileDiffLoaded) {
      $0.gitHistory?.presentedDiff?.diff = diff
    }
    await store.receive(\.gitHistory.loaded) {
      $0.gitHistory?.isLoading = false
      $0.gitHistory?.snapshot = snapshot
    }
  }

  @Test func referenceWithVisiblePanePresentsDiffWithoutReload() async {
    let worktree = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let diff = makeFileDiff()
    let historyCalls = LockIsolated(0)
    var initialState = makeState(repositories: [repository], selection: .worktree(worktree.id))
    initialState.inspectorPane = .history
    initialState.inspectorPresented = true
    initialState.gitHistory = RepositoriesFeature.GitHistoryState(
      worktreeID: worktree.id, snapshot: makeSnapshot())
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
      $0.gitClient.commitHistory = { _, _ in
        historyCalls.withValue { $0 += 1 }
        return GitHistorySnapshot(
          commits: [], upstreamRef: nil, aheadCount: 0, isTruncated: false)
      }
      $0.gitClient.uncommittedFileDiff = { _, _ in diff }
    }

    await store.send(
      .openTerminalFileReference(worktreeID: worktree.id, path: "B.swift", line: nil)
    )
    await store.receive(\.gitHistory.fileTapped) {
      $0.gitHistory?.presentedDiff = RepositoriesFeature.PresentedFileDiff(
        source: .uncommitted, filePath: "B.swift")
    }
    await store.receive(\.gitHistory.fileDiffLoaded) {
      $0.gitHistory?.presentedDiff?.diff = diff
    }
    #expect(historyCalls.value == 0)
  }

  @Test func referenceForUnselectedWorktreeIsIgnored() async {
    let wt1 = makeWorktree(id: "/tmp/repo/wt1", name: "wt1")
    let wt2 = makeWorktree(id: "/tmp/repo/wt2", name: "wt2")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [wt1, wt2])
    let store = TestStore(
      initialState: makeState(repositories: [repository], selection: .worktree(wt1.id))
    ) {
      RepositoriesFeature()
    } withDependencies: {
      $0.sidebarStructureAutoRecompute = false
    }

    await store.send(
      .openTerminalFileReference(worktreeID: wt2.id, path: "supacode/A.swift", line: 1)
    )
  }
}
