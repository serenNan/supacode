import ComposableArchitecture
import SwiftUI

/// Persistent bottom-left sidebar entry for the Todo panel. Tapping the button
/// expands a self-contained rounded rectangle above it hosting the same
/// checklist content as the standalone Todos window — no popover chrome.
struct TodoPanelBottomBar: View {
  let store: StoreOf<TodoPanelFeature>
  @State private var isExpanded = false

  var body: some View {
    VStack(spacing: 0) {
      if isExpanded {
        TodoPanelView(store: store)
          .frame(height: 320)
          .background(.background, in: RoundedRectangle(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(.separator)
          }
          .padding(.horizontal, 8)
          .padding(.top, 8)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      toggleButton
    }
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
  }

  private var toggleButton: some View {
    Button {
      isExpanded.toggle()
    } label: {
      Label("Todos", systemImage: "checklist")
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isExpanded ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    .help("Show the active session's todos (⌥⌘T)")
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}
