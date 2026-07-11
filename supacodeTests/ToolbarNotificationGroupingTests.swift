import Foundation
import IdentifiedCollections
import OrderedCollections
import Sharing
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

@MainActor
struct ToolbarNotificationGroupingTests {
  @Test func groupsNotificationsByRepositoryAndWorktreeInDisplayOrder() {
    let repoAPath = "/tmp/repo-a"
    let repoBPath = "/tmp/repo-b"

    let repoAMain = makeWorktree(id: repoAPath, name: "main", repoRoot: repoAPath)
    let repoAOne = makeWorktree(id: "\(repoAPath)/one", name: "one", repoRoot: repoAPath)
    let repoATwo = makeWorktree(id: "\(repoAPath)/two", name: "two", repoRoot: repoAPath)

    let repoBMain = makeWorktree(id: repoBPath, name: "main", repoRoot: repoBPath)
    let repoBOne = makeWorktree(id: "\(repoBPath)/one", name: "one", repoRoot: repoBPath)

    let repoA = makeRepository(id: repoAPath, name: "Repo A", worktrees: [repoAMain, repoAOne, repoATwo])
    let repoB = makeRepository(id: repoBPath, name: "Repo B", worktrees: [repoBMain, repoBOne])

    var state = RepositoriesFeature.State(reconciledRepositories: [repoA, repoB])
    state.repositoryRoots = [repoA.rootURL, repoB.rootURL]
    state.$sidebar.withLock { sidebar in
      sidebar.sections[repoB.id] = .init()
      sidebar.sections[repoA.id] = .init(
        buckets: [
          .unpinned: .init(
            items: [
              repoATwo.id: .init(),
              repoAOne.id: .init(),
            ]
          )
        ]
      )
    }

    setRowNotifications(
      &state, id: repoAOne.id,
      notifications: [
        WorktreeTerminalNotification(
          surfaceID: UUID(), title: "A1", body: "done", createdAt: .distantPast, isRead: true
        )
      ])
    setRowNotifications(
      &state, id: repoATwo.id,
      notifications: [
        WorktreeTerminalNotification(surfaceID: UUID(), title: "A2", body: "done", createdAt: .distantPast)
      ])
    setRowNotifications(
      &state, id: repoBOne.id,
      notifications: [
        WorktreeTerminalNotification(
          surfaceID: UUID(), title: "B1", body: "done", createdAt: .distantPast, isRead: true
        )
      ])

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.map(\.id) == [repoB.id, repoA.id])
    #expect(groups[0].worktrees.map(\.id) == [repoBOne.id])
    #expect(groups[1].worktrees.map(\.id) == [repoATwo.id, repoAOne.id])
    #expect(groups[1].unseenWorktreeCount == 1)
  }

  @Test func omitsArchivedAndEmptyNotificationGroups() {
    let repoAPath = "/tmp/repo-a"
    let repoBPath = "/tmp/repo-b"

    let repoAMain = makeWorktree(id: repoAPath, name: "main", repoRoot: repoAPath)
    let repoAArchived = makeWorktree(id: "\(repoAPath)/archived", name: "archived", repoRoot: repoAPath)
    let repoBMain = makeWorktree(id: repoBPath, name: "main", repoRoot: repoBPath)
    let repoBEmpty = makeWorktree(id: "\(repoBPath)/empty", name: "empty", repoRoot: repoBPath)

    let repoA = makeRepository(id: repoAPath, name: "Repo A", worktrees: [repoAMain, repoAArchived])
    let repoB = makeRepository(id: repoBPath, name: "Repo B", worktrees: [repoBMain, repoBEmpty])

    var state = RepositoriesFeature.State(reconciledRepositories: [repoA, repoB])
    state.repositoryRoots = [repoA.rootURL, repoB.rootURL]
    state.$sidebar.withLock { sidebar in
      sidebar.insert(
        worktree: repoAArchived.id,
        in: repoA.id,
        bucket: .archived,
        item: .init(archivedAt: Date(timeIntervalSince1970: 1_000_000))
      )
    }

    setRowNotifications(
      &state, id: repoAArchived.id,
      notifications: [
        WorktreeTerminalNotification(surfaceID: UUID(), title: "Archived", body: "hidden", createdAt: .distantPast)
      ])

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.isEmpty)
  }

  @Test func unseenWorktreeCountUsesUnreadNotificationsOnly() {
    let repoPath = "/tmp/repo"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let readOnly = makeWorktree(id: "\(repoPath)/read-only", name: "read-only", repoRoot: repoPath)
    let mixed = makeWorktree(id: "\(repoPath)/mixed", name: "mixed", repoRoot: repoPath)

    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, readOnly, mixed])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    setRowNotifications(
      &state, id: readOnly.id,
      notifications: [
        WorktreeTerminalNotification(
          surfaceID: UUID(), title: "Read 1", body: "done", createdAt: .distantPast, isRead: true
        )
      ])
    setRowNotifications(
      &state, id: mixed.id,
      notifications: [
        WorktreeTerminalNotification(
          surfaceID: UUID(), title: "Read 2", body: "done", createdAt: .distantPast, isRead: true
        ),
        WorktreeTerminalNotification(
          surfaceID: UUID(), title: "Unread", body: "new", createdAt: .distantPast, isRead: false
        ),
      ])

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.count == 1)
    #expect(groups[0].notificationCount == 3)
    #expect(groups[0].unseenWorktreeCount == 1)
  }

  @Test func keepsReadOnlyNotificationsInGroups() {
    let repoPath = "/tmp/repo"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)

    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    setRowNotifications(
      &state, id: feature.id,
      notifications: [
        WorktreeTerminalNotification(
          surfaceID: UUID(), title: "Read", body: "kept", createdAt: .distantPast, isRead: true
        )
      ])

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.map(\.id) == [repo.id])
    #expect(groups[0].worktrees.map(\.id) == [feature.id])
    #expect(groups[0].unseenWorktreeCount == 0)
  }

  @Test func usesResolvedSidebarTitleWhenCustomTitleIsSet() {
    // A user-set custom title (from `WorktreeCustomizationFeature.save`)
    // flows into `SidebarItemFeature.State.customTitle` via the reconcile
    // pass; the notification popover must show that resolved title, not
    // the raw branch name.
    let repoPath = "/tmp/repo-customized"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature/x", repoRoot: repoPath)

    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    state.sidebarItems[id: feature.id]?.customTitle = "Spicy"

    setRowNotifications(
      &state, id: feature.id,
      notifications: [
        WorktreeTerminalNotification(surfaceID: UUID(), title: "T", body: "done", createdAt: .distantPast)
      ])

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.first?.worktrees.first?.name == "Spicy")
  }

  @Test func resolvesRepositoryColorAndCustomTitleFromSection() {
    let repoPath = "/tmp/repo-tinted"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])

    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]
    state.$sidebar.withLock { sidebar in
      sidebar.sections[repo.id] = .init(title: "Custom Repo", color: .teal)
    }

    setRowNotifications(
      &state, id: feature.id,
      notifications: [
        WorktreeTerminalNotification(surfaceID: UUID(), title: "T", body: "done", createdAt: .distantPast)
      ])

    let group = state.computeToolbarNotificationGroups().first
    #expect(group?.isFolder == false)
    #expect(group?.name == "Custom Repo")
    #expect(group?.color == .teal)
  }

  @Test func resolvesFolderHeaderFromSyntheticRow() {
    // A folder's custom title / tint live on its synthetic row, not the repo
    // section, so the header must resolve there to match the sidebar.
    let folderURL = URL(fileURLWithPath: "/tmp/notif-folder")
    let folderID = Repository.folderWorktreeID(for: folderURL)
    let folderRepo = Repository(
      id: RepositoryID(folderURL.path(percentEncoded: false)),
      rootURL: folderURL,
      name: "notif-folder",
      worktrees: IdentifiedArray(
        uniqueElements: [
          Worktree(
            id: folderID,
            name: "notif-folder",
            detail: "",
            workingDirectory: folderURL,
            repositoryRootURL: folderURL
          )
        ]
      ),
      isGitRepository: false
    )

    var state = RepositoriesFeature.State(reconciledRepositories: [folderRepo])
    state.repositoryRoots = [folderRepo.rootURL]
    state.sidebarItems[id: folderID]?.customTitle = "My Folder"
    state.sidebarItems[id: folderID]?.customTint = .purple

    setRowNotifications(
      &state, id: folderID,
      notifications: [
        WorktreeTerminalNotification(surfaceID: UUID(), title: "T", body: "done", createdAt: .distantPast)
      ])

    let group = state.computeToolbarNotificationGroups().first
    #expect(group?.isFolder == true)
    #expect(group?.name == "My Folder")
    #expect(group?.color == .purple)
  }

  @Test func includesRemoteRepositoryNotifications() {
    // Remote repos are host-keyed and absent from `repositoryRoots` (which is
    // local-only), so `orderedRepositoryIDs()` doesn't list them. The toolbar
    // bell must still surface their notifications.
    let host = RemoteHost(alias: "devbox")
    let repoID = "remote:devbox:/home/me/proj"
    let feature = Worktree(
      id: "devbox:/home/me/proj/feature",
      name: "feature",
      detail: "",
      workingDirectory: URL(fileURLWithPath: "/home/me/proj/feature"),
      repositoryRootURL: URL(fileURLWithPath: "/home/me/proj"),
      host: host
    )
    let repo = Repository(
      id: RepositoryID(repoID),
      rootURL: URL(fileURLWithPath: "/home/me/proj"),
      name: "proj",
      worktrees: IdentifiedArray(uniqueElements: [feature]),
      isGitRepository: true,
      host: host
    )
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    // repositoryRoots intentionally left empty, the remote repo isn't in it.

    setRowNotifications(
      &state, id: feature.id,
      notifications: [
        WorktreeTerminalNotification(surfaceID: UUID(), title: "Remote", body: "needs input", createdAt: .distantPast)
      ])

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.map(\.id) == [RepositoryID(repoID)])
    #expect(groups.first?.worktrees.map(\.id) == [feature.id])
    #expect(groups.first?.unseenWorktreeCount == 1)
  }

  @Test func resolvesSessionTitlesForNotificationTabs() {
    let repoPath = "/tmp/repo-sessions"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let renamedTab = TerminalTabID()
    let blankTab = TerminalTabID()
    let unrelatedTab = TerminalTabID()
    state.sidebarItems[id: feature.id]?.tabsSummary = WorktreeTabsSummary(
      tabs: [
        .init(id: renamedTab, title: "  Fix login flow  ", icon: nil, tint: nil),
        .init(id: blankTab, title: "   ", icon: nil, tint: nil),
        .init(id: unrelatedTab, title: "zsh", icon: nil, tint: nil),
      ],
      selectedTabID: renamedTab
    )

    let renamed = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: renamedTab, title: "claude", body: "waiting", createdAt: .distantPast
    )
    let blank = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: blankTab, title: "claude", body: "waiting", createdAt: .distantPast
    )
    let untabbed = WorktreeTerminalNotification(
      surfaceID: UUID(), title: "claude", body: "waiting", createdAt: .distantPast
    )
    setRowNotifications(&state, id: feature.id, notifications: [renamed, blank, untabbed])

    let group = state.computeToolbarNotificationGroups().first?.worktrees.first

    // Only referenced tabs with a non-blank title make it in; blank / gone
    // tabs fall back to the agent name in the row.
    #expect(group?.tabTitles == [renamedTab: "Fix login flow"])
    #expect(group?.sessionTitle(for: renamed) == "Fix login flow")
    #expect(group?.sessionTitle(for: blank) == nil)
    #expect(group?.sessionTitle(for: untabbed) == nil)
  }

  @Test func unreferencedTabTitleChurnKeepsGroupsEqual() {
    // `tabsSnapshotChanged` now invalidates the notification-groups cache; the
    // Equatable diff must stay blind to title churn on tabs no notification
    // points at, or every shell-title update would re-render the inspector.
    let repoPath = "/tmp/repo-churn"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let notifiedTab = TerminalTabID()
    let noisyTab = TerminalTabID()
    setRowNotifications(
      &state, id: feature.id,
      notifications: [
        WorktreeTerminalNotification(
          surfaceID: UUID(), tabID: notifiedTab, title: "claude", body: "waiting", createdAt: .distantPast
        )
      ])
    state.sidebarItems[id: feature.id]?.tabsSummary = WorktreeTabsSummary(
      tabs: [
        .init(id: notifiedTab, title: "Session", icon: nil, tint: nil),
        .init(id: noisyTab, title: "make build", icon: nil, tint: nil),
      ],
      selectedTabID: notifiedTab
    )
    let before = state.computeToolbarNotificationGroups()

    state.sidebarItems[id: feature.id]?.tabsSummary.tabs[1] =
      .init(id: noisyTab, title: "make test", icon: nil, tint: nil)
    #expect(state.computeToolbarNotificationGroups() == before)

    state.sidebarItems[id: feature.id]?.tabsSummary.tabs[0] =
      .init(id: notifiedTab, title: "Renamed Session", icon: nil, tint: nil)
    #expect(state.computeToolbarNotificationGroups() != before)
  }

  @Test func tabsSnapshotChangedInvalidatesNotificationGroupsCache() {
    // The session headline reads tab titles out of the cached groups, so a
    // rename must trigger the post-reduce recompute.
    let action = SidebarItemFeature.Action.tabsSnapshotChanged(WorktreeTabsSummary())
    #expect(action.cacheInvalidations == .toolbarNotificationGroups)
  }

  @Test func includesRepoLevelIssueNotificationsWithoutWorktreeNotifications() {
    let repoPath = "/tmp/repo-a"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo A", worktrees: [main])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]
    state.issueNotifications = [
      RepositoryIssueNotification(
        id: UUID(),
        repositoryID: repo.id,
        issueNumber: 630,
        title: "New comment on #630",
        body: "Clamp notification body",
        url: "https://github.com/octo/repo/issues/630",
        createdAt: .distantPast
      )
    ]

    let groups = state.computeToolbarNotificationGroups()

    #expect(groups.map(\.id) == [repo.id])
    #expect(groups.first?.worktrees.isEmpty == true)
    #expect(groups.first?.issueNotifications.count == 1)
    #expect(groups.first?.notificationCount == 1)
    #expect(groups.first?.unreadCount == 1)
  }

  @Test func clustersNotificationsBySessionNewestFirst() {
    let repoPath = "/tmp/repo-clusters"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let tabA = TerminalTabID()
    let tabB = TerminalTabID()
    let newestA = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tabA, title: "claude", body: "a3", createdAt: Date(timeIntervalSince1970: 30)
    )
    let onlyB = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tabB, title: "claude", body: "b1", createdAt: Date(timeIntervalSince1970: 25)
    )
    let middleA = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tabA, title: "claude", body: "a2", createdAt: Date(timeIntervalSince1970: 20)
    )
    let oldestA = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tabA, title: "claude", body: "a1", createdAt: Date(timeIntervalSince1970: 10)
    )
    // Storage order: newest first, matching WorktreeTerminalState's insert-at-0.
    setRowNotifications(&state, id: feature.id, notifications: [newestA, onlyB, middleA, oldestA])

    let clusters = state.computeToolbarNotificationGroups().first?.worktrees.first?.sessionClusters

    #expect(clusters?.map(\.id) == [.tab(tabA), .tab(tabB)])
    #expect(clusters?.first?.notifications.map(\.body) == ["a3", "a2", "a1"])
    #expect(clusters?.first?.olderCount == 2)
    #expect(clusters?.last?.olderCount == 0)
  }

  @Test func clustersFallBackToSurfaceWhenTabIsGone() {
    let repoPath = "/tmp/repo-surface-clusters"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let surface1 = UUID()
    let surface2 = UUID()
    let newer = WorktreeTerminalNotification(
      surfaceID: surface1, title: "claude", body: "s1-new", createdAt: Date(timeIntervalSince1970: 20)
    )
    let other = WorktreeTerminalNotification(
      surfaceID: surface2, title: "claude", body: "s2", createdAt: Date(timeIntervalSince1970: 15)
    )
    let older = WorktreeTerminalNotification(
      surfaceID: surface1, title: "claude", body: "s1-old", createdAt: Date(timeIntervalSince1970: 10)
    )
    setRowNotifications(&state, id: feature.id, notifications: [newer, other, older])

    let clusters = state.computeToolbarNotificationGroups().first?.worktrees.first?.sessionClusters

    #expect(clusters?.map(\.id) == [.surface(surface1), .surface(surface2)])
    #expect(clusters?.first?.notifications.map(\.body) == ["s1-new", "s1-old"])
  }

  @Test func clusterCountsHiddenUnreadForCollapsedHint() {
    let repoPath = "/tmp/repo-hidden-unread"
    let main = makeWorktree(id: repoPath, name: "main", repoRoot: repoPath)
    let feature = makeWorktree(id: "\(repoPath)/feature", name: "feature", repoRoot: repoPath)
    let repo = makeRepository(id: repoPath, name: "Repo", worktrees: [main, feature])
    var state = RepositoriesFeature.State(reconciledRepositories: [repo])
    state.repositoryRoots = [repo.rootURL]

    let tab = TerminalTabID()
    // The newest (visible) row is unread too, but only *hidden* rows count
    // toward the expand-control hint.
    let newestUnread = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tab, title: "claude", body: "new", createdAt: Date(timeIntervalSince1970: 30)
    )
    let hiddenUnread = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tab, title: "claude", body: "mid", createdAt: Date(timeIntervalSince1970: 20)
    )
    let hiddenRead = WorktreeTerminalNotification(
      surfaceID: UUID(), tabID: tab, title: "claude", body: "old", createdAt: Date(timeIntervalSince1970: 10),
      isRead: true
    )
    setRowNotifications(&state, id: feature.id, notifications: [newestUnread, hiddenUnread, hiddenRead])

    let clusters = state.computeToolbarNotificationGroups().first?.worktrees.first?.sessionClusters

    #expect(clusters?.count == 1)
    #expect(clusters?.first?.hiddenUnreadCount == 1)
  }

  private func setRowNotifications(
    _ state: inout RepositoriesFeature.State,
    id: SidebarItemID,
    notifications: [WorktreeTerminalNotification]
  ) {
    let hasUnseen = notifications.contains(where: { !$0.isRead })
    state.sidebarItems[id: id]?.notifications = IdentifiedArrayOf(uniqueElements: notifications)
    state.sidebarItems[id: id]?.hasUnseenNotifications = hasUnseen
  }

  private func makeWorktree(
    id: String,
    name: String,
    repoRoot: String
  ) -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot)
    )
  }

  private func makeRepository(
    id: String,
    name: String,
    worktrees: [Worktree]
  ) -> Repository {
    Repository(
      id: RepositoryID(id),
      rootURL: URL(fileURLWithPath: id),
      name: name,
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }
}

@MainActor
struct ScriptMenuIdentityTests {
  // The running-script set drives the cached NSMenu's `.id`, so dropping it
  // would let the toolbar dropdown go stale after a signal-based stop (#573).
  @Test func runningScriptSetParticipatesInIdentity() {
    let running = UUID()
    let base = WorktreeDetailView.ScriptMenuIdentity(
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      repoFingerprints: [],
      globalFingerprints: [],
      runningScriptIDs: []
    )
    let withRunning = WorktreeDetailView.ScriptMenuIdentity(
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      repoFingerprints: [],
      globalFingerprints: [],
      runningScriptIDs: [running]
    )

    #expect(base != withRunning)
    #expect(
      base
        == WorktreeDetailView.ScriptMenuIdentity(
          rootURL: URL(fileURLWithPath: "/tmp/repo"),
          repoFingerprints: [],
          globalFingerprints: [],
          runningScriptIDs: []
        ))
  }
}
