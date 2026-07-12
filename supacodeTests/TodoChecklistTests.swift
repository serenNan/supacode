import Testing

@testable import supacode

struct TodoChecklistTests {
  @Test func groupsUncheckedItemsUnderNearestHeading() {
    let text = """
      # Todos

      ## Now
      - [ ] first task
      - [ ] second task

      ## Later
      - [ ] third task
      """
    let sections = TodoChecklist.parse(text)
    #expect(sections.map(\.title) == ["Now", "Later"])
    #expect(sections[0].items.map(\.text) == ["first task", "second task"])
    #expect(sections[1].items.map(\.text) == ["third task"])
  }

  @Test func excludesCheckedItemsFromDisplay() {
    let text = """
      ## Mixed
      - [ ] open
      - [x] done lowercase
      - [X] done uppercase
      """
    let sections = TodoChecklist.parse(text)
    #expect(sections.count == 1)
    #expect(sections[0].items.map(\.text) == ["open"])
  }

  @Test func dropsHeadingsWithNoUncheckedItems() {
    let text = """
      ## All done
      - [x] finished

      ## Empty

      ## Active
      - [ ] pending
      """
    let sections = TodoChecklist.parse(text)
    #expect(sections.map(\.title) == ["Active"])
  }

  @Test func acceptsAlternateBulletsAndIndentation() {
    let text = """
      ## Bullets
      * [ ] star bullet
      + [ ] plus bullet
        - [ ] indented dash
      """
    let sections = TodoChecklist.parse(text)
    #expect(sections[0].items.map(\.text) == ["star bullet", "plus bullet", "indented dash"])
  }

  @Test func ignoresNonChecklistLines() {
    let text = """
      ## Notes
      Some prose that is not a task.
      - a plain list item without a checkbox
      - [] missing space is not a task marker
      - [ ] real task
      """
    let sections = TodoChecklist.parse(text)
    #expect(sections[0].items.map(\.text) == ["real task"])
  }

  @Test func itemsBeforeAnyHeadingHaveNilTitle() {
    let text = """
      - [ ] headerless task
      ## Titled
      - [ ] titled task
      """
    let sections = TodoChecklist.parse(text)
    #expect(sections.map(\.title) == [nil, "Titled"])
    #expect(sections[0].items.map(\.text) == ["headerless task"])
  }

  @Test func togglingFlipsUncheckedToChecked() {
    #expect(TodoChecklist.toggling(line: "- [ ] ship it") == "- [x] ship it")
  }

  @Test func togglingFlipsCheckedToUnchecked() {
    #expect(TodoChecklist.toggling(line: "- [x] ship it") == "- [ ] ship it")
    #expect(TodoChecklist.toggling(line: "- [X] ship it") == "- [ ] ship it")
  }

  @Test func togglingPreservesSurroundingBytes() {
    #expect(TodoChecklist.toggling(line: "  * [ ] task  📅 2026-07-12") == "  * [x] task  📅 2026-07-12")
    #expect(TodoChecklist.toggling(line: "\t+ [x]  spaced text ") == "\t+ [ ]  spaced text ")
  }

  @Test func togglingReturnsNilForNonTaskLines() {
    #expect(TodoChecklist.toggling(line: "just prose") == nil)
    #expect(TodoChecklist.toggling(line: "- plain list item") == nil)
    #expect(TodoChecklist.toggling(line: "- [] not a marker") == nil)
    #expect(TodoChecklist.toggling(line: "## heading") == nil)
  }

  @Test func recordsLineIndicesAndRawLines() {
    let text = "## H\n- [x] done\n- [ ] open one\n\n- [ ] open two"
    let sections = TodoChecklist.parse(text)
    let items = sections[0].items
    #expect(items.map(\.lineIndex) == [2, 4])
    #expect(items.map(\.rawLine) == ["- [ ] open one", "- [ ] open two"])
  }
}
