import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import SupacodeSettingsFeature
@testable import supacode

@MainActor
struct AppFeatureTodoPanelTests {
  @Test(.dependencies) func selectedWorktreeChangedForwardsSelectionToTodoPanel() async {
    let worktree = makeWorktree()
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktree: worktree),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }
    store.exhaustivity = .off

    await store.send(.repositories(.delegate(.selectedWorktreeChanged(worktree))))
    await store.receive(\.todoPanel.selectionChanged) {
      $0.todoPanel.selection = .init(
        worktreeRootURL: URL(fileURLWithPath: "/tmp/repo/wt-1"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
        repositoryName: "repo"
      )
    }
    await store.finish()
  }

  @Test(.dependencies) func deselectionForwardsNilSelectionToTodoPanel() async {
    let worktree = makeWorktree()
    var initialState = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    initialState.todoPanel.selection = .init(
      worktreeRootURL: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo"),
      repositoryName: "repo"
    )
    let store = TestStore(initialState: initialState) {
      AppFeature()
    }
    store.exhaustivity = .off

    await store.send(.repositories(.delegate(.selectedWorktreeChanged(nil))))
    await store.receive(\.todoPanel.selectionChanged) {
      $0.todoPanel.selection = nil
    }
    await store.finish()
  }

  @Test(.dependencies) func sendToActiveSessionInsertsTaskTextIntoFocusedSurface() async {
    let worktree = makeWorktree()
    let inserted = LockIsolated<[String]>([])
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktree: worktree),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.insertTextInFocusedSurface = { target, text in
        #expect(target == worktree)
        inserted.withValue { $0.append(text) }
        return true
      }
    }

    await store.send(.todoPanel(.delegate(.sendToActiveSession("fix the flaky test"))))
    await store.finish()
    #expect(inserted.value == ["fix the flaky test"])
  }

  @Test(.dependencies) func sendToActiveSessionWithoutFocusedSurfaceShowsNotice() async {
    let worktree = makeWorktree()
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktree: worktree),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.insertTextInFocusedSurface = { _, _ in false }
    }

    await store.send(.todoPanel(.delegate(.sendToActiveSession("nobody listening"))))
    await store.receive(\.todoPanel.sendToSessionFailed) {
      $0.todoPanel.isSendUnavailableNoticeVisible = true
    }
    await store.finish()
  }

  @Test(.dependencies) func sendToActiveSessionWithoutSelectionShowsNotice() async {
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: RepositoriesFeature.State(),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.insertTextInFocusedSurface = { _, _ in
        Issue.record("insertTextInFocusedSurface should not be called without a selection")
        return true
      }
    }

    await store.send(.todoPanel(.delegate(.sendToActiveSession("no session"))))
    await store.receive(\.todoPanel.sendToSessionFailed) {
      $0.todoPanel.isSendUnavailableNoticeVisible = true
    }
    await store.finish()
  }

  private func makeWorktree() -> Worktree {
    Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
  }

  private func makeRepositoriesState(worktree: Worktree) -> RepositoriesFeature.State {
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "repo",
      worktrees: [worktree]
    )
    var state = RepositoriesFeature.State()
    state.repositories = [repository]
    state.selection = .worktree(worktree.id)
    return state
  }
}
