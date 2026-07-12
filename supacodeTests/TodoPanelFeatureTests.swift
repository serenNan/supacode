import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct TodoPanelFeatureTests {
  private nonisolated static let worktreeRoot = URL(filePath: "/tmp/todo-panel/worktree")
  private nonisolated static let repositoryRoot = URL(filePath: "/tmp/todo-panel/repo")
  private nonisolated static let worktreeTodo = worktreeRoot.appending(path: "TODO.md")
  private nonisolated static let repositoryTodo = repositoryRoot.appending(path: "TODO.md")

  private nonisolated static var selection: TodoPanelFeature.Selection {
    .init(
      worktreeRootURL: worktreeRoot,
      repositoryRootURL: repositoryRoot,
      repositoryName: "supacode"
    )
  }

  @Test func selectionLoadsWorktreeFileFirst() async {
    let store = TestStore(initialState: TodoPanelFeature.State(isPanelOpen: true)) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.read = { url in
        url == Self.worktreeTodo ? "## Now\n- [ ] from worktree" : "## Now\n- [ ] from repo"
      }
    }

    await store.send(.selectionChanged(Self.selection)) {
      $0.selection = Self.selection
    }
    await store.receive(\.loaded) {
      $0.displayedFile = .init(url: Self.worktreeTodo, origin: .worktree)
      $0.sections = [
        .init(
          title: "Now",
          items: [.init(text: "from worktree", lineIndex: 1, rawLine: "- [ ] from worktree")]
        )
      ]
    }
  }

  @Test func selectionFallsBackToRepositoryFile() async {
    let store = TestStore(initialState: TodoPanelFeature.State(isPanelOpen: true)) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.read = { url in
        url == Self.repositoryTodo ? "- [ ] from repo" : nil
      }
    }

    await store.send(.selectionChanged(Self.selection)) {
      $0.selection = Self.selection
    }
    await store.receive(\.loaded) {
      $0.displayedFile = .init(url: Self.repositoryTodo, origin: .repository)
      $0.sections = [
        .init(title: nil, items: [.init(text: "from repo", lineIndex: 0, rawLine: "- [ ] from repo")])
      ]
    }
  }

  @Test func missingFilesEverywhereShowEmptyState() async {
    let store = TestStore(
      initialState: TodoPanelFeature.State(
        isPanelOpen: true,
        displayedFile: .init(url: Self.worktreeTodo, origin: .worktree),
        sections: [.init(title: nil, items: [.init(text: "stale", lineIndex: 0, rawLine: "- [ ] stale")])]
      )
    ) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.read = { _ in nil }
    }

    await store.send(.selectionChanged(Self.selection)) {
      $0.selection = Self.selection
    }
    await store.receive(\.loaded) {
      $0.displayedFile = nil
      $0.sections = []
    }
  }

  @Test func selectionChangeRetargetsWatcherToCandidateFiles() async {
    let watched = LockIsolated<[[URL]]>([])
    let store = TestStore(initialState: TodoPanelFeature.State(isPanelOpen: true)) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.read = { _ in nil }
      $0.todoFile.watch = { urls in
        watched.withValue { $0.append(urls) }
      }
    }

    await store.send(.selectionChanged(Self.selection)) {
      $0.selection = Self.selection
    }
    await store.receive(\.loaded)

    #expect(watched.value == [[Self.worktreeTodo, Self.repositoryTodo]])
  }

  @Test func fileChangeEventReloadsWhilePanelIsOpen() async {
    let (events, eventsContinuation) = AsyncStream<Void>.makeStream()
    let contents = LockIsolated("- [ ] first version")
    let store = TestStore(initialState: TodoPanelFeature.State(selection: Self.selection)) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.read = { url in
        url == Self.worktreeTodo ? contents.value : nil
      }
      $0.todoFile.events = { events }
    }

    await store.send(.panelAppeared) {
      $0.isPanelOpen = true
      $0.openPresentations = 1
    }
    await store.receive(\.loaded) {
      $0.displayedFile = .init(url: Self.worktreeTodo, origin: .worktree)
      $0.sections = [
        .init(
          title: nil,
          items: [.init(text: "first version", lineIndex: 0, rawLine: "- [ ] first version")]
        )
      ]
    }

    contents.setValue("- [ ] second version")
    eventsContinuation.yield(())
    await store.receive(\.fileChangeDetected)
    await store.receive(\.loaded) {
      $0.sections = [
        .init(
          title: nil,
          items: [.init(text: "second version", lineIndex: 0, rawLine: "- [ ] second version")]
        )
      ]
    }

    await store.send(.panelClosed) {
      $0.isPanelOpen = false
      $0.openPresentations = 0
    }
    eventsContinuation.finish()
  }

  private struct ToggleCall: Equatable {
    var url: URL
    var lineIndex: Int
    var rawLine: String
  }

  @Test func markDoneRemovesItemOptimisticallyAndWritesBack() async {
    let toggled = LockIsolated<[ToggleCall]>([])
    let first = TodoChecklist.Item(text: "first", lineIndex: 1, rawLine: "- [ ] first")
    let second = TodoChecklist.Item(text: "second", lineIndex: 2, rawLine: "- [ ] second")
    let store = TestStore(
      initialState: TodoPanelFeature.State(
        isPanelOpen: true,
        selection: Self.selection,
        displayedFile: .init(url: Self.worktreeTodo, origin: .worktree),
        sections: [.init(title: "Now", items: [first, second])]
      )
    ) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.toggleLine = { url, lineIndex, rawLine in
        toggled.withValue {
          $0.append(ToggleCall(url: url, lineIndex: lineIndex, rawLine: rawLine))
        }
      }
    }

    await store.send(.markDoneTapped(first)) {
      $0.sections = [.init(title: "Now", items: [second])]
    }

    #expect(
      toggled.value == [ToggleCall(url: Self.worktreeTodo, lineIndex: 1, rawLine: "- [ ] first")]
    )
  }

  @Test func markDoneDropsSectionWhenItBecomesEmpty() async {
    let only = TodoChecklist.Item(text: "only", lineIndex: 1, rawLine: "- [ ] only")
    let store = TestStore(
      initialState: TodoPanelFeature.State(
        isPanelOpen: true,
        selection: Self.selection,
        displayedFile: .init(url: Self.worktreeTodo, origin: .worktree),
        sections: [.init(title: "Now", items: [only])]
      )
    ) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.toggleLine = { _, _, _ in }
    }

    await store.send(.markDoneTapped(only)) {
      $0.sections = []
    }
  }

  @Test func markDoneConflictReloadsInsteadOfApplying() async {
    let item = TodoChecklist.Item(text: "contested", lineIndex: 0, rawLine: "- [ ] contested")
    let store = TestStore(
      initialState: TodoPanelFeature.State(
        isPanelOpen: true,
        selection: Self.selection,
        displayedFile: .init(url: Self.worktreeTodo, origin: .worktree),
        sections: [.init(title: nil, items: [item])]
      )
    ) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.read = { url in
        url == Self.worktreeTodo ? "- [ ] rewritten meanwhile" : nil
      }
      $0.todoFile.toggleLine = { _, _, _ in throw TodoFileConflictError() }
    }

    await store.send(.markDoneTapped(item)) {
      $0.sections = []
    }
    await store.receive(\.markDoneFailed)
    await store.receive(\.loaded) {
      $0.sections = [
        .init(
          title: nil,
          items: [
            .init(text: "rewritten meanwhile", lineIndex: 0, rawLine: "- [ ] rewritten meanwhile")
          ]
        )
      ]
    }
  }

  @Test func taskTappedDelegatesTextForTheActiveSession() async {
    let item = TodoChecklist.Item(text: "ship the panel", lineIndex: 3, rawLine: "- [ ] ship the panel")
    let store = TestStore(
      initialState: TodoPanelFeature.State(
        isPanelOpen: true,
        selection: Self.selection,
        displayedFile: .init(url: Self.worktreeTodo, origin: .worktree),
        sections: [.init(title: nil, items: [item])]
      )
    ) {
      TodoPanelFeature()
    }

    await store.send(.taskTapped(item))
    await store.receive(\.delegate.sendToActiveSession)
  }

  @Test func sendFailureShowsNoticeUntilDismissed() async {
    let store = TestStore(initialState: TodoPanelFeature.State(isPanelOpen: true)) {
      TodoPanelFeature()
    }

    await store.send(.sendToSessionFailed) {
      $0.isSendUnavailableNoticeVisible = true
    }
    await store.send(.noticeDismissed) {
      $0.isSendUnavailableNoticeVisible = false
    }
  }

  @Test func panelClosedStopsWatching() async {
    let stopped = LockIsolated(0)
    let store = TestStore(
      initialState: TodoPanelFeature.State(isPanelOpen: true, openPresentations: 1, selection: Self.selection)
    ) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.stopWatching = {
        stopped.withValue { $0 += 1 }
      }
    }

    await store.send(.panelClosed) {
      $0.isPanelOpen = false
      $0.openPresentations = 0
    }

    #expect(stopped.value == 1)
  }

  @Test func closingOneOfTwoPresentationsKeepsWatching() async {
    let stopped = LockIsolated(0)
    let store = TestStore(
      initialState: TodoPanelFeature.State(isPanelOpen: true, openPresentations: 2, selection: Self.selection)
    ) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.stopWatching = {
        stopped.withValue { $0 += 1 }
      }
    }

    await store.send(.panelClosed) {
      $0.openPresentations = 1
    }
    #expect(stopped.value == 0)

    await store.send(.panelClosed) {
      $0.isPanelOpen = false
      $0.openPresentations = 0
    }
    #expect(stopped.value == 1)
  }

  @Test func extraPanelClosedWithoutOpenPresentationsIsHarmless() async {
    let stopped = LockIsolated(0)
    let store = TestStore(initialState: TodoPanelFeature.State()) {
      TodoPanelFeature()
    } withDependencies: {
      $0.todoFile.stopWatching = {
        stopped.withValue { $0 += 1 }
      }
    }

    await store.send(.panelClosed)
    #expect(stopped.value == 1)
  }
}
