import SwiftUI

/// Window-menu entry for the Todo panel. `Window(id:)` scenes are
/// single-instance, so re-invoking focuses the existing window.
struct TodoPanelMenuButton: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Todos") {
      openWindow(id: WindowID.todoPanel)
    }
    .keyboardShortcut("t", modifiers: [.option, .command])
    .help("Show the active session's TODO.md checklist (⌥⌘T)")
  }
}
