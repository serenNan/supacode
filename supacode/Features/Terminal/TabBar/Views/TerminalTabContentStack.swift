import SwiftUI

struct TerminalTabContentStack<Content: View>: View {
  let tabs: [TerminalTabItem]
  let selectedTabId: TerminalTabID
  let content: (TerminalTabID) -> Content

  init(
    tabs: [TerminalTabItem],
    selectedTabId: TerminalTabID,
    @ViewBuilder content: @escaping (TerminalTabID) -> Content
  ) {
    self.tabs = tabs
    self.selectedTabId = selectedTabId
    self.content = content
  }

  var body: some View {
    // Keep every tab's terminal surface mounted and only toggle visibility, so
    // switching tabs never tears down / re-hosts the GhosttyKit surface. A
    // re-host forces a fresh layout pass that resizes the surface and fires a
    // spurious SIGWINCH; width-sensitive TUIs (Claude Code, aider) then redraw
    // at the wrong column count — the "terminal content is horizontally cut off
    // after switching tabs" bug (upstream #425). Native Ghostty keeps tab
    // surfaces resident too. Render-pause for the hidden tabs is already handled
    // by WorktreeTerminalState.applySurfaceActivity (occlusion keyed on the
    // selected tab), so mounted-but-hidden tabs don't keep drawing.
    ZStack {
      ForEach(tabs) { tab in
        let isSelected = tab.id == selectedTabId
        content(tab.id)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .opacity(isSelected ? 1 : 0)
          .allowsHitTesting(isSelected)
          .accessibilityHidden(!isSelected)
      }
    }
  }

  static func selectedTabID(in tabs: [TerminalTabItem], selectedTabId: TerminalTabID) -> TerminalTabID? {
    tabs.contains { $0.id == selectedTabId } ? selectedTabId : nil
  }
}
