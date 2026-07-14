import ComposableArchitecture
import Foundation
import SupacodeSettingsShared
import Testing

@testable import supacode

@MainActor
struct SidebarItemFeatureTests {
  // MARK: - Equality-guarded data deltas.

  @Test func diffStatsChangeMutatesOnceThenNoOps() async {
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    await store.send(.diffStatsChanged(added: 3, removed: 1)) {
      $0.addedLines = 3
      $0.removedLines = 1
    }
    // Same payload: no-op.
    await store.send(.diffStatsChanged(added: 3, removed: 1))
  }

  @Test func lifecycleEqualityGuardSkipsNoOps() async {
    var state = makeState(name: "feature")
    state.lifecycle = .archiving
    let store = TestStore(initialState: state) {
      SidebarItemFeature()
    }
    await store.send(.lifecycleChanged(.archiving))
    await store.send(.lifecycleChanged(.idle)) {
      $0.lifecycle = .idle
    }
  }

  @Test func terminalProjectionReplacesRunningScriptsWholesale() async {
    // The projection is the single writer: whatever set it carries replaces
    // the row's, so a stale mirror can't survive a reconcile (#573).
    let scriptA = UUID()
    let scriptB = UUID()
    var state = makeState(name: "feature")
    state.runningScripts = [.init(id: scriptA, tint: .orange)]
    let store = TestStore(initialState: state) {
      SidebarItemFeature()
    }
    await store.send(
      .terminalProjectionChanged(
        makeProjection(runningScripts: [.init(id: scriptB, tint: .blue)])
      )
    ) {
      $0.hasTerminalProjection = true
      $0.runningScripts = [.init(id: scriptB, tint: .blue)]
    }
    // Identical set: no-op.
    await store.send(
      .terminalProjectionChanged(
        makeProjection(runningScripts: [.init(id: scriptB, tint: .blue)])
      )
    )
    // Empty set clears the phantom.
    await store.send(.terminalProjectionChanged(makeProjection(runningScripts: []))) {
      $0.runningScripts = []
    }
  }

  @Test func agentSnapshotEqualityGuardSkipsNoOps() async {
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    let instance = AgentPresenceFeature.AgentInstance(
      agent: .claude,
      activity: .busy
    )
    await store.send(.agentSnapshotChanged(.init(agents: [instance], isWorking: true))) {
      $0.agentSnapshot = .init(agents: [instance], isWorking: true)
    }
    // Same payload: no-op.
    await store.send(.agentSnapshotChanged(.init(agents: [instance], isWorking: true)))
    // isWorking flip only.
    await store.send(.agentSnapshotChanged(.init(agents: [instance], isWorking: false))) {
      $0.agentSnapshot = .init(agents: [instance], isWorking: false)
    }
  }

  @Test func agentErrorFlagTracksSnapshot() async {
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    let errored = AgentPresenceFeature.AgentInstance(agent: .claude, activity: .error)
    await store.send(.agentSnapshotChanged(.init(agents: [errored], hasError: true))) {
      $0.agentSnapshot = .init(agents: [errored], hasError: true)
    }
    #expect(store.state.hasAgentError)

    // A restart clears it and puts the row back to work.
    let busy = AgentPresenceFeature.AgentInstance(agent: .claude, activity: .busy)
    await store.send(.agentSnapshotChanged(.init(agents: [busy], isWorking: true))) {
      $0.agentSnapshot = .init(agents: [busy], isWorking: true)
    }
    #expect(!store.state.hasAgentError)
    #expect(store.state.hasAgentActivity)
  }

  @Test func compactingFlagTracksItsOwnChannel() async {
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    // Compaction rides its own action since `RowSnapshot` omits it.
    await store.send(.agentCompactingChanged(true)) {
      $0.isCompacting = true
    }
    // Same value: no-op.
    await store.send(.agentCompactingChanged(true))
    await store.send(.agentCompactingChanged(false)) {
      $0.isCompacting = false
    }
  }

  // MARK: - Terminal projection per-field guards.

  @Test func terminalProjectionEachFieldGuardedIndependently() async {
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    let surface1 = UUID()
    let surface2 = UUID()
    let notif = WorktreeTerminalNotification(
      surfaceID: surface1,
      title: "Notification",
      body: "hi",
      createdAt: Date(timeIntervalSince1970: 0)
    )
    let baseline = makeProjection(surfaceIDs: [surface1])
    await store.send(.terminalProjectionChanged(baseline)) {
      $0.hasTerminalProjection = true
      $0.surfaceIDs = [surface1]
    }
    // Identical projection: no mutation.
    await store.send(.terminalProjectionChanged(baseline))
    // surfaceIDs alone changes.
    await store.send(
      .terminalProjectionChanged(makeProjection(surfaceIDs: [surface1, surface2]))
    ) {
      $0.surfaceIDs = [surface1, surface2]
    }
    // isProgressBusy alone changes (and `isTaskRunning` derives from it).
    await store.send(
      .terminalProjectionChanged(
        makeProjection(surfaceIDs: [surface1, surface2], isProgressBusy: true)
      )
    ) {
      $0.isProgressBusy = true
    }
    // hasUnseenNotifications flips alone (independent of `notifications`).
    await store.send(
      .terminalProjectionChanged(
        makeProjection(surfaceIDs: [surface1, surface2], isProgressBusy: true, hasUnseenNotifications: true)
      )
    ) {
      $0.hasUnseenNotifications = true
    }
    // notifications flip alone.
    await store.send(
      .terminalProjectionChanged(
        makeProjection(
          surfaceIDs: [surface1, surface2],
          isProgressBusy: true,
          hasUnseenNotifications: true,
          notifications: [notif]
        )
      )
    ) {
      $0.notifications = [notif]
    }
    // runningScripts flip alone.
    let scriptID = UUID()
    await store.send(
      .terminalProjectionChanged(
        makeProjection(
          surfaceIDs: [surface1, surface2],
          isProgressBusy: true,
          hasUnseenNotifications: true,
          notifications: [notif],
          runningScripts: [.init(id: scriptID, tint: .blue)]
        )
      )
    ) {
      $0.runningScripts = [.init(id: scriptID, tint: .blue)]
    }
  }

  // MARK: - Stale-PR guard.

  @Test func pullRequestChangedDropsResultWhenBranchHasFlipped() async {
    // Post-flip state: row's branch is already "feature/y", a live PR is in place,
    // and a late result from the prior "feature/x" query is about to arrive.
    var state = makeState(name: "feature/y")
    state.branchName = "feature/y"
    let livePR = GithubPullRequest(
      number: 12,
      title: "Live",
      state: "OPEN",
      additions: 1,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://example.com/pull/12",
      headRefName: "feature/y",
      baseRefName: "main",
      commitsCount: 1,
      authorLogin: "tester",
      statusCheckRollup: nil,
      mergeQueueEntry: nil
    )
    state.pullRequest = livePR
    let store = TestStore(initialState: state) {
      SidebarItemFeature()
    }
    let stalePR = GithubPullRequest(
      number: 99,
      title: "Stale",
      state: "OPEN",
      additions: 0,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://example.com/pull/99",
      headRefName: "feature/x",
      baseRefName: "main",
      commitsCount: 1,
      authorLogin: "tester",
      statusCheckRollup: nil,
      mergeQueueEntry: nil
    )
    // Late stale result must not replace the live PR.
    await store.send(.pullRequestChanged(stalePR, branchAtQueryTime: "feature/x"))
    #expect(store.state.pullRequest == livePR)
  }

  @Test func pullRequestChangedClearsWatermarkOnSuccessAndOnIdenticalReissue() async {
    var state = makeState(name: "feature")
    state.branchName = "feature"
    let store = TestStore(initialState: state) {
      SidebarItemFeature()
    }
    let pullRequest = GithubPullRequest(
      number: 1,
      title: "First",
      state: "OPEN",
      additions: 1,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://example.com/pull/1",
      headRefName: "feature",
      baseRefName: "main",
      commitsCount: 1,
      authorLogin: "tester",
      statusCheckRollup: nil,
      mergeQueueEntry: nil
    )
    await store.send(.pullRequestQueryStarted(branch: "feature")) {
      $0.pullRequestBranchAtQueryTime = "feature"
    }
    // Success path: PR is written and watermark cleared.
    await store.send(.pullRequestChanged(pullRequest, branchAtQueryTime: "feature")) {
      $0.pullRequest = pullRequest
      $0.pullRequestBranchAtQueryTime = nil
    }
    // Identical-payload reissue with a re-armed watermark: PR unchanged, watermark still cleared.
    await store.send(.pullRequestQueryStarted(branch: "feature")) {
      $0.pullRequestBranchAtQueryTime = "feature"
    }
    await store.send(.pullRequestChanged(pullRequest, branchAtQueryTime: "feature")) {
      $0.pullRequestBranchAtQueryTime = nil
    }
  }

  @Test func pullRequestQueryStartedEqualityGuardSkipsNoOps() async {
    var state = makeState(name: "feature")
    state.pullRequestBranchAtQueryTime = "feature"
    let store = TestStore(initialState: state) {
      SidebarItemFeature()
    }
    // Same branch: no-op.
    await store.send(.pullRequestQueryStarted(branch: "feature"))
    await store.send(.pullRequestQueryStarted(branch: "other")) {
      $0.pullRequestBranchAtQueryTime = "other"
    }
  }

  // MARK: - UI-scalar guards.

  @Test func dragSessionGuardSkipsNoOps() async {
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    await store.send(.dragSessionChanged(isDragging: true)) {
      $0.isDragging = true
    }
    // Same drag state: no-op.
    await store.send(.dragSessionChanged(isDragging: true))
  }

  // MARK: - Tab-strip snapshot.

  @Test func tabsSnapshotUpdatesStateAndCollapsesOnSingleTab() async {
    let tabA = TerminalTabID()
    let tabB = TerminalTabID()
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    let twoTabs = WorktreeTabsSummary(
      tabs: [
        .init(id: tabA, title: "Claude Code", icon: nil, tint: nil),
        .init(id: tabB, title: "Tests", icon: nil, tint: nil),
      ],
      selectedTabID: tabB
    )
    await store.send(.tabsSnapshotChanged(twoTabs)) {
      $0.tabsSummary = twoTabs
    }

    await store.send(.tabListExpansionToggled) {
      $0.isTabListExpanded = true
    }

    // Identical snapshot: no-op.
    await store.send(.tabsSnapshotChanged(twoTabs))

    // Dropping to one tab resets the expansion.
    let oneTab = WorktreeTabsSummary(
      tabs: [.init(id: tabA, title: "Claude Code", icon: nil, tint: nil)],
      selectedTabID: tabA
    )
    await store.send(.tabsSnapshotChanged(oneTab)) {
      $0.tabsSummary = oneTab
      $0.isTabListExpanded = false
    }
  }

  @Test func tabAgentsSnapshotReplacesWholesaleAndSkipsNoOps() async {
    let tabA = TerminalTabID()
    let tabB = TerminalTabID()
    let claude = AgentPresenceFeature.AgentInstance(agent: .claude, activity: .busy)
    let store = TestStore(initialState: makeState(name: "feature")) {
      SidebarItemFeature()
    }
    await store.send(.tabAgentsChanged([tabA: [claude]])) {
      $0.tabAgents = [tabA: [claude]]
    }
    // Same payload: no-op.
    await store.send(.tabAgentsChanged([tabA: [claude]]))
    // The fan-out sends the full per-row map, so a new snapshot replaces it
    // wholesale (agent moved to tabB; tabA drops out).
    await store.send(.tabAgentsChanged([tabB: [claude]])) {
      $0.tabAgents = [tabB: [claude]]
    }
    // Agents gone: map drains.
    await store.send(.tabAgentsChanged([:])) {
      $0.tabAgents = [:]
    }
  }

  // MARK: - Helpers.

  private func makeState(name: String) -> SidebarItemFeature.State {
    SidebarItemFeature.State(
      id: SidebarItemID("/tmp/repo/wt-\(name)"),
      repositoryID: "/tmp/repo",
      kind: .gitWorktree,
      name: name,
      branchName: name,
      subtitle: nil,
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-\(name)"),
      repositoryAccent: nil,
      isMainWorktree: false,
      isPinned: false,
      hasMergedBadge: false
    )
  }

  private func makeProjection(
    surfaceIDs: [UUID] = [],
    isProgressBusy: Bool = false,
    hasUnseenNotifications: Bool = false,
    notifications: IdentifiedArrayOf<WorktreeTerminalNotification> = [],
    runningScripts: IdentifiedArrayOf<SidebarItemFeature.State.RunningScript> = []
  ) -> WorktreeRowProjection {
    WorktreeRowProjection(
      surfaceIDs: surfaceIDs,
      isProgressBusy: isProgressBusy,
      hasUnseenNotifications: hasUnseenNotifications,
      notifications: notifications,
      runningScripts: runningScripts
    )
  }
}
