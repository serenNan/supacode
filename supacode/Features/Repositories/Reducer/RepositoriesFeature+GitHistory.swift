import ComposableArchitecture
import Foundation

private nonisolated enum GitHistoryCancelID: Hashable {
  case load
  case detail
  case uncommittedFiles
}

extension RepositoriesFeature {
  /// History for one worktree only — the selected one. Cleared whenever the
  /// pane hides or the selection empties, so a stale list never flashes on
  /// reopen and hidden panes cost zero git calls.
  struct GitHistoryState: Equatable, Sendable {
    var worktreeID: Worktree.ID
    var snapshot: GitHistorySnapshot?
    var isLoading = false
    var loadError: String?
    var expandedCommitHash: String?
    var expandedDetail: GitCommitDetail?
    var detailError: String?
    /// Uncommitted +/- line counts mirrored from the sidebar row's diff stats
    /// (same watcher pipeline) so the pane's "Uncommitted Changes" node costs
    /// no extra git calls.
    var uncommittedAdded: Int?
    var uncommittedRemoved: Int?
    var isUncommittedExpanded = false
    var uncommittedFiles: [GitCommitFileChange]?
    var uncommittedFilesError: String?
  }

  @CasePathable
  enum GitHistoryAction: Equatable, Sendable {
    case refresh
    case loaded(worktreeID: Worktree.ID, GitHistorySnapshot)
    case failed(worktreeID: Worktree.ID, message: String)
    case commitTapped(hash: String)
    case detailLoaded(worktreeID: Worktree.ID, hash: String, GitCommitDetail)
    case detailFailed(worktreeID: Worktree.ID, hash: String, message: String)
    case uncommittedTapped
    case uncommittedFilesLoaded(worktreeID: Worktree.ID, [GitCommitFileChange])
    case uncommittedFilesFailed(worktreeID: Worktree.ID, message: String)
  }

  static let gitHistoryCommitLimit = 200

  var gitHistoryReducer: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .gitHistory(.refresh):
        guard state.isGitHistoryPaneVisible,
          let worktree = state.worktree(for: state.selectedWorktreeID)
        else {
          return .none
        }
        return startGitHistoryLoad(state: &state, worktree: worktree)

      case .gitHistory(.loaded(let worktreeID, let snapshot)):
        guard state.gitHistory?.worktreeID == worktreeID else { return .none }
        state.gitHistory?.isLoading = false
        state.gitHistory?.snapshot = snapshot
        return .none

      case .gitHistory(.failed(let worktreeID, let message)):
        guard state.gitHistory?.worktreeID == worktreeID else { return .none }
        state.gitHistory?.isLoading = false
        state.gitHistory?.loadError = message
        return .none

      case .gitHistory(.commitTapped(let hash)):
        guard var history = state.gitHistory,
          let worktree = state.worktree(for: history.worktreeID)
        else {
          return .none
        }
        let isCollapse = history.expandedCommitHash == hash
        history.expandedCommitHash = isCollapse ? nil : hash
        history.expandedDetail = nil
        history.detailError = nil
        history.isUncommittedExpanded = false
        history.uncommittedFiles = nil
        history.uncommittedFilesError = nil
        state.gitHistory = history
        if isCollapse {
          return .cancel(id: GitHistoryCancelID.detail)
        }
        let client = historyGitClient(for: worktree)
        let worktreeURL = worktree.workingDirectory
        let worktreeID = worktree.id
        return .run { send in
          do {
            let detail = try await client.commitDetail(worktreeURL, hash)
            await send(.gitHistory(.detailLoaded(worktreeID: worktreeID, hash: hash, detail)))
          } catch {
            await send(
              .gitHistory(
                .detailFailed(
                  worktreeID: worktreeID, hash: hash, message: error.localizedDescription)))
          }
        }
        .cancellable(id: GitHistoryCancelID.detail, cancelInFlight: true)

      case .gitHistory(.detailLoaded(let worktreeID, let hash, let detail)):
        guard state.gitHistory?.worktreeID == worktreeID,
          state.gitHistory?.expandedCommitHash == hash
        else {
          return .none
        }
        state.gitHistory?.expandedDetail = detail
        return .none

      case .gitHistory(.detailFailed(let worktreeID, let hash, let message)):
        guard state.gitHistory?.worktreeID == worktreeID,
          state.gitHistory?.expandedCommitHash == hash
        else {
          return .none
        }
        state.gitHistory?.detailError = message
        return .none

      case .gitHistory(.uncommittedTapped):
        guard var history = state.gitHistory,
          let worktree = state.worktree(for: history.worktreeID)
        else {
          return .none
        }
        let isCollapse = history.isUncommittedExpanded
        history.isUncommittedExpanded = !isCollapse
        history.uncommittedFiles = nil
        history.uncommittedFilesError = nil
        history.expandedCommitHash = nil
        history.expandedDetail = nil
        history.detailError = nil
        state.gitHistory = history
        if isCollapse {
          return .cancel(id: GitHistoryCancelID.uncommittedFiles)
        }
        return .merge(
          .cancel(id: GitHistoryCancelID.detail),
          loadUncommittedFiles(worktree: worktree)
        )

      case .gitHistory(.uncommittedFilesLoaded(let worktreeID, let files)):
        guard state.gitHistory?.worktreeID == worktreeID,
          state.gitHistory?.isUncommittedExpanded == true
        else {
          return .none
        }
        state.gitHistory?.uncommittedFiles = files
        return .none

      case .gitHistory(.uncommittedFilesFailed(let worktreeID, let message)):
        guard state.gitHistory?.worktreeID == worktreeID,
          state.gitHistory?.isUncommittedExpanded == true
        else {
          return .none
        }
        state.gitHistory?.uncommittedFilesError = message
        return .none

      case .sidebarItems(
        .element(id: let worktreeID, action: .diffStatsChanged(let added, let removed))):
        guard state.gitHistory?.worktreeID == worktreeID else { return .none }
        state.gitHistory?.uncommittedAdded = added
        state.gitHistory?.uncommittedRemoved = removed
        return .none

      case .worktreeInfoEvent(.branchChanged(let worktreeID)),
        .worktreeInfoEvent(.filesChanged(let worktreeID)):
        guard state.isGitHistoryPaneVisible,
          worktreeID == state.selectedWorktreeID,
          let worktree = state.worktree(for: worktreeID)
        else {
          return .none
        }
        return startGitHistoryLoad(state: &state, worktree: worktree)

      default:
        // Reconciliation: this reducer sits after the ones mutating inspector
        // state and selection, so visibility / selection transitions land here
        // without enumerating every action that can cause them.
        guard state.isGitHistoryPaneVisible,
          let worktree = state.worktree(for: state.selectedWorktreeID)
        else {
          guard state.gitHistory != nil else { return .none }
          state.gitHistory = nil
          return .merge(
            .cancel(id: GitHistoryCancelID.load),
            .cancel(id: GitHistoryCancelID.detail),
            .cancel(id: GitHistoryCancelID.uncommittedFiles)
          )
        }
        guard state.gitHistory?.worktreeID != worktree.id else { return .none }
        return startGitHistoryLoad(state: &state, worktree: worktree)
      }
    }
  }

  private func startGitHistoryLoad(state: inout State, worktree: Worktree) -> Effect<Action> {
    if state.gitHistory?.worktreeID == worktree.id {
      state.gitHistory?.isLoading = true
      state.gitHistory?.loadError = nil
    } else {
      var history = GitHistoryState(worktreeID: worktree.id, isLoading: true)
      let row = state.sidebarItems[id: worktree.id]
      history.uncommittedAdded = row?.addedLines
      history.uncommittedRemoved = row?.removedLines
      state.gitHistory = history
    }
    let client = historyGitClient(for: worktree)
    let worktreeURL = worktree.workingDirectory
    let worktreeID = worktree.id
    let loadEffect: Effect<Action> = .run { send in
      do {
        let snapshot = try await client.commitHistory(worktreeURL, Self.gitHistoryCommitLimit)
        await send(.gitHistory(.loaded(worktreeID: worktreeID, snapshot)))
      } catch {
        await send(.gitHistory(.failed(worktreeID: worktreeID, message: error.localizedDescription)))
      }
    }
    .cancellable(id: GitHistoryCancelID.load, cancelInFlight: true)
    // An expanded uncommitted node tracks the same refresh triggers as the list,
    // so its file breakdown never goes stale behind the +/- counts.
    guard state.gitHistory?.isUncommittedExpanded == true else { return loadEffect }
    return .merge(loadEffect, loadUncommittedFiles(worktree: worktree))
  }

  private func loadUncommittedFiles(worktree: Worktree) -> Effect<Action> {
    let client = historyGitClient(for: worktree)
    let worktreeURL = worktree.workingDirectory
    let worktreeID = worktree.id
    return .run { send in
      do {
        let files = try await client.uncommittedFiles(worktreeURL)
        await send(.gitHistory(.uncommittedFilesLoaded(worktreeID: worktreeID, files)))
      } catch {
        await send(
          .gitHistory(
            .uncommittedFilesFailed(worktreeID: worktreeID, message: error.localizedDescription)))
      }
    }
    .cancellable(id: GitHistoryCancelID.uncommittedFiles, cancelInFlight: true)
  }

  /// Host-aware flavor mirroring the main file's private `gitClient(for:)`:
  /// SSH for a remote worktree so history queries run on the host.
  private func historyGitClient(for worktree: Worktree) -> GitClientDependency {
    @Dependency(GitClientDependency.self) var gitClient
    guard let host = worktree.host else {
      return gitClient
    }
    return .ssh(host: host)
  }
}

extension RepositoriesFeature.State {
  var isGitHistoryPaneVisible: Bool {
    inspectorPresented && inspectorPane == .history
  }
}
