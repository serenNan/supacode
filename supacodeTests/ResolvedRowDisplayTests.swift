import SupacodeSettingsShared
import Testing

@testable import supacode

@MainActor
struct ResolvedRowDisplayTests {
  // MARK: - Folder rows.

  @Test func folderKindRendersBranchAsTitleAndDropsSubtitle() {
    let resolved = ResolvedRowDisplay(
      kind: .folder,
      branchName: "Documents",
      worktreeName: "Documents",
      isMainWorktree: true,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.name == "Documents")
    #expect(resolved.subtitle == .none)
  }

  @Test func folderKindIgnoresHighlightTagSinceFolderIsTheRepo() {
    let resolved = ResolvedRowDisplay(
      kind: .folder,
      branchName: "Notes",
      worktreeName: nil,
      isMainWorktree: true,
      isPinned: true,
      hideSubtitle: false,
      hideSubtitleOnMatch: false,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "Notes", repoColor: nil, hostInfo: nil)
    )
    #expect(resolved.subtitle == .none)
  }

  // MARK: - Title resolution (worktree folder name, branch in the subtitle).

  @Test func titleIsWorktreeFolderNameAndBranchMovesToSubtitle() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "scratch",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.name == "scratch")
    #expect(resolved.subtitle == .plain("feature/foo"))
  }

  @Test func customTitleBeatsFolderName() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "main",
      worktreeName: "supacode",
      isMainWorktree: true,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true,
      customTitle: "My Repo"
    )
    #expect(resolved.name == "My Repo")
    #expect(resolved.subtitle == .plain("main"))
  }

  @Test func nilWorktreeNameFallsBackToBranchTitle() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: nil,
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.name == "feature/foo")
  }

  // MARK: - Per-repo subtitle path (no highlight tag).

  @Test func plainSubtitleHidesWhenWorktreeMatchesBranchLastComponentAndFlagOn() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "foo",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.name == "foo")
    #expect(resolved.subtitle == .none)
  }

  @Test func plainSubtitleKeepsBranchOnMatchWhenFlagOff() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "foo",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: false
    )
    #expect(resolved.subtitle == .plain("feature/foo"))
  }

  @Test func plainSubtitleSuppressedUnconditionallyByHideSubtitle() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "scratch",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: true,
      hideSubtitleOnMatch: false
    )
    #expect(resolved.subtitle == .none)
  }

  // MARK: - Highlight trail resolution.

  @Test func highlightDropsRepoTagWhenItEqualsTheTitle() {
    // A hoisted main worktree titles itself with the repo folder name; the
    // repo tag would read as a duplicate, so the subtitle keeps just the branch.
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "main",
      worktreeName: "supacode",
      isMainWorktree: true,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: .blue, hostInfo: nil)
    )
    #expect(resolved.name == "supacode")
    #expect(resolved.subtitle == .plain("main"))
  }

  @Test func highlightKeepsRepoTagForRemoteEvenWhenItEqualsTheTitle() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "main",
      worktreeName: "supacode",
      isMainWorktree: true,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: nil, hostInfo: "dev@build-box")
    )
    #expect(
      resolved.subtitle
        == .highlight(repo: "supacode", repoColor: nil, trail: "main", hostInfo: "dev@build-box")
    )
  }

  @Test func highlightTrailHidesOnMatchWhenFlagOn() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "foo",
      isMainWorktree: false,
      isPinned: true,
      hideSubtitle: false,
      hideSubtitleOnMatch: true,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: nil, hostInfo: nil)
    )
    guard case .highlight(_, _, let trail, _) = resolved.subtitle else {
      Issue.record("Expected .highlight subtitle")
      return
    }
    #expect(trail == nil)
  }

  @Test func highlightTrailKeepsBranchOnMatchWhenFlagOff() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "foo",
      isMainWorktree: false,
      isPinned: true,
      hideSubtitle: false,
      hideSubtitleOnMatch: false,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: nil, hostInfo: nil)
    )
    guard case .highlight(_, _, let trail, _) = resolved.subtitle else {
      Issue.record("Expected .highlight subtitle")
      return
    }
    #expect(trail == "feature/foo")
  }

  @Test func highlightTrailIsBranchWhenNoMatch() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "scratch",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: nil, hostInfo: nil)
    )
    guard case .highlight(_, _, let trail, _) = resolved.subtitle else {
      Issue.record("Expected .highlight subtitle")
      return
    }
    #expect(resolved.name == "scratch")
    #expect(trail == "feature/foo")
  }

  // MARK: - Hide-on-match parity across the two render paths.

  @Test func hideOnMatchParityBetweenHighlightAndPlainPaths() {
    let plain = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "foo",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    let highlight = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature/foo",
      worktreeName: "foo",
      isMainWorktree: false,
      isPinned: true,
      hideSubtitle: false,
      hideSubtitleOnMatch: true,
      highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: nil, hostInfo: nil)
    )
    #expect(plain.subtitle == .none)
    if case .highlight(_, _, let trail, _) = highlight.subtitle {
      #expect(trail == nil)
    } else {
      Issue.record("Expected .highlight subtitle for the hoisted path")
    }
  }

  // MARK: - Accent resolution.

  @Test func accentIsMainForMainWorktreeRegardlessOfPin() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "main",
      worktreeName: nil,
      isMainWorktree: true,
      isPinned: true,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.accent == .main)
  }

  @Test func accentIsPinnedWhenPinnedAndNotMain() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature",
      worktreeName: "scratch",
      isMainWorktree: false,
      isPinned: true,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.accent == .pinned)
  }

  @Test func accentIsDefaultWhenNeitherMainNorPinned() {
    let resolved = ResolvedRowDisplay(
      kind: .gitWorktree,
      branchName: "feature",
      worktreeName: "scratch",
      isMainWorktree: false,
      isPinned: false,
      hideSubtitle: false,
      hideSubtitleOnMatch: true
    )
    #expect(resolved.accent == .default)
  }
}
