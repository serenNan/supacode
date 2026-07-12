import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import SupacodeSettingsFeature
@testable import supacode

@MainActor
struct AppFeatureTerminalFileReferenceTests {
  @Test(.dependencies) func fileReferenceClickedForwardsToRepositories() async {
    let worktree = Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "repo",
      worktrees: [worktree]
    )
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    repositoriesState.reconcileSidebarForTesting()
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositoriesState,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    // No selection: the reference is forwarded, and repositories drops it.
    await store.send(
      .terminalEvent(.fileReferenceClicked(worktreeID: worktree.id, path: "A.swift", line: 3))
    )
    await store.receive(\.repositories.openTerminalFileReference)
  }
}
