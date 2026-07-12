import ComposableArchitecture
import Foundation

/// Shows the active session's todo checklist in the standalone Todo panel
/// window: worktree file first, repository primary checkout as fallback,
/// live-refreshed while the panel is open.
@Reducer
struct TodoPanelFeature {
  struct Selection: Equatable, Sendable {
    var worktreeRootURL: URL?
    var repositoryRootURL: URL?
    var repositoryName: String?

    /// Remote worktrees have no local paths to read, so both candidate
    /// roots stay nil and the panel shows its empty state.
    nonisolated init(worktree: Worktree, repositoryName: String?) {
      let isLocal = worktree.host == nil
      self.init(
        worktreeRootURL: isLocal ? worktree.workingDirectory : nil,
        repositoryRootURL: isLocal ? worktree.repositoryRootURL : nil,
        repositoryName: repositoryName
      )
    }

    nonisolated init(worktreeRootURL: URL?, repositoryRootURL: URL?, repositoryName: String?) {
      self.worktreeRootURL = worktreeRootURL
      self.repositoryRootURL = repositoryRootURL
      self.repositoryName = repositoryName
    }
  }

  struct DisplayedFile: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
      case worktree
      case repository
    }

    var url: URL
    var origin: Origin
  }

  @ObservableState
  struct State: Equatable {
    var isPanelOpen = false
    /// The popover and the standalone window can be open at once; watchers
    /// tear down only when the last presentation closes.
    var openPresentations = 0
    var selection: Selection?
    var displayedFile: DisplayedFile?
    var sections: [TodoChecklist.Section] = []
    var isSendUnavailableNoticeVisible = false
  }

  enum Action: Equatable, Sendable {
    case panelAppeared
    case panelClosed
    case selectionChanged(Selection?)
    case fileChangeDetected
    case loaded(DisplayedFile?, [TodoChecklist.Section])
    case markDoneTapped(TodoChecklist.Item)
    case markDoneFailed
    case taskTapped(TodoChecklist.Item)
    case sendToSessionFailed
    case noticeDismissed
    case delegate(Delegate)

    @CasePathable
    enum Delegate: Equatable, Sendable {
      case sendToActiveSession(String)
    }
  }

  @Dependency(TodoFileClient.self) private var todoFile

  private nonisolated enum CancelID: Hashable, Sendable {
    case events
    case load
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .panelAppeared:
        state.openPresentations += 1
        state.isPanelOpen = true
        return .merge(
          watchCandidates(of: state.selection),
          load(state.selection),
          .run { send in
            for await _ in await todoFile.events() {
              await send(.fileChangeDetected)
            }
          }
          .cancellable(id: CancelID.events, cancelInFlight: true)
        )

      case .panelClosed:
        state.openPresentations = max(0, state.openPresentations - 1)
        guard state.openPresentations == 0 else { return .none }
        state.isPanelOpen = false
        return .merge(
          .cancel(id: CancelID.events),
          .cancel(id: CancelID.load),
          .run { _ in await todoFile.stopWatching() }
        )

      case .selectionChanged(let selection):
        state.selection = selection
        guard state.isPanelOpen else { return .none }
        return .merge(watchCandidates(of: selection), load(selection))

      case .fileChangeDetected:
        return load(state.selection)

      case .loaded(let displayedFile, let sections):
        state.displayedFile = displayedFile
        state.sections = sections
        return .none

      case .markDoneTapped(let item):
        guard let displayedFile = state.displayedFile else { return .none }
        state.sections = Self.removing(item: item, from: state.sections)
        return .run { send in
          do {
            try await todoFile.toggleLine(displayedFile.url, item.lineIndex, item.rawLine)
          } catch {
            await send(.markDoneFailed)
          }
        }

      case .markDoneFailed:
        return load(state.selection)

      case .taskTapped(let item):
        return .send(.delegate(.sendToActiveSession(item.text)))

      case .sendToSessionFailed:
        state.isSendUnavailableNoticeVisible = true
        return .none

      case .noticeDismissed:
        state.isSendUnavailableNoticeVisible = false
        return .none

      case .delegate:
        return .none
      }
    }
  }

  /// The panel's file resolution order: the session's worktree copy wins,
  /// the repository's primary checkout is the fallback.
  private static func candidateURLs(of selection: Selection?) -> [URL] {
    guard let selection else { return [] }
    return [selection.worktreeRootURL, selection.repositoryRootURL]
      .compactMap { $0?.appending(path: "TODO.md") }
  }

  private func watchCandidates(of selection: Selection?) -> Effect<Action> {
    let candidates = Self.candidateURLs(of: selection)
    return .run { _ in await todoFile.watch(candidates) }
  }

  private func load(_ selection: Selection?) -> Effect<Action> {
    let candidates = Self.candidateURLs(of: selection)
    let origins: [DisplayedFile.Origin] =
      selection?.worktreeRootURL != nil ? [.worktree, .repository] : [.repository]
    return .run { send in
      for (url, origin) in zip(candidates, origins) {
        if let content = await todoFile.read(url) {
          await send(.loaded(.init(url: url, origin: origin), TodoChecklist.parse(content)))
          return
        }
      }
      await send(.loaded(nil, []))
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  private static func removing(
    item: TodoChecklist.Item,
    from sections: [TodoChecklist.Section]
  ) -> [TodoChecklist.Section] {
    sections.compactMap { section in
      var section = section
      section.items.removeAll { $0 == item }
      return section.items.isEmpty ? nil : section
    }
  }
}
