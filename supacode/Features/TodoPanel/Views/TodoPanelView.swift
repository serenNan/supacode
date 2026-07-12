import ComposableArchitecture
import SwiftUI

/// Standalone window listing the active session's unchecked todo items.
/// The checkbox marks an item done in the file; the task text hands it to the
/// session's agent input.
struct TodoPanelView: View {
  let store: StoreOf<TodoPanelFeature>

  var body: some View {
    content
      .navigationTitle(title)
      .safeAreaInset(edge: .bottom) {
        if store.isSendUnavailableNoticeVisible {
          sendUnavailableNotice
        }
      }
      .onAppear { store.send(.panelAppeared) }
      .onDisappear { store.send(.panelClosed) }
  }

  private var title: String {
    if let repositoryName = store.selection?.repositoryName {
      return "Todos — \(repositoryName)"
    }
    return "Todos"
  }

  @ViewBuilder
  private var content: some View {
    if store.selection == nil {
      ContentUnavailableView(
        "No Session Selected",
        systemImage: "checklist",
        description: Text("Select a worktree session to see its TODO.md.")
      )
    } else if let displayedFile = store.displayedFile {
      checklist(displayedFile: displayedFile)
    } else {
      ContentUnavailableView(
        "No TODO.md Found",
        systemImage: "checklist",
        description: Text(
          "Add a TODO.md at the worktree or repository root and it will show up here."
        )
      )
    }
  }

  @ViewBuilder
  private func checklist(displayedFile: TodoPanelFeature.DisplayedFile) -> some View {
    if store.sections.isEmpty {
      ContentUnavailableView(
        "All Done",
        systemImage: "checkmark.circle",
        description: Text("Every task in \(displayedFile.url.lastPathComponent) is checked off.")
      )
    } else {
      List {
        ForEach(store.sections, id: \.self) { section in
          Section {
            ForEach(section.items, id: \.lineIndex) { item in
              TodoPanelRow(
                item: item,
                markDone: { store.send(.markDoneTapped(item)) },
                sendToSession: { store.send(.taskTapped(item)) }
              )
            }
          } header: {
            if let title = section.title {
              Text(title)
            }
          }
        }
      }
      .listStyle(.inset)
    }
  }

  private var sendUnavailableNotice: some View {
    HStack {
      Label(
        "No focused terminal to receive the task.",
        systemImage: "exclamationmark.bubble"
      )
      Spacer()
      Button("OK") {
        store.send(.noticeDismissed)
      }
      .help("Dismiss this notice")
    }
    .padding(8)
    .background(.bar)
  }
}

private struct TodoPanelRow: View {
  let item: TodoChecklist.Item
  let markDone: () -> Void
  let sendToSession: () -> Void

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Button(action: markDone) {
        Image(systemName: "circle")
          .foregroundStyle(.secondary)
          .accessibilityLabel("Mark done")
      }
      .buttonStyle(.plain)
      .help("Mark done — checks this item off in TODO.md")
      Button(action: sendToSession) {
        Text(item.text)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Insert this task into the active session's input")
    }
  }
}
