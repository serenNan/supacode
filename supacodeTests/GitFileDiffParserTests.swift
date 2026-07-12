import Foundation
import Testing

@testable import supacode

struct GitFileDiffParserTests {
  @Test func parsesMultiHunkDiffWithKindsAndLineNumbers() {
    let output = """
      diff --git a/Sources/Foo.swift b/Sources/Foo.swift
      index 1234567..89abcde 100644
      --- a/Sources/Foo.swift
      +++ b/Sources/Foo.swift
      @@ -1,4 +1,5 @@ func foo()
       line one
      -line two
      +line two changed
      +line two point five
       line three
      @@ -10,2 +11,2 @@
       ctx
      -removed
      +added
      """

    let diff = GitClient.parseFileDiff(output)

    #expect(!diff.isBinary)
    #expect(diff.hunks.count == 2)
    #expect(diff.hunks[0].header == "@@ -1,4 +1,5 @@ func foo()")
    #expect(
      diff.hunks[0].lines == [
        GitDiffLine(kind: .context, text: "line one", oldNumber: 1, newNumber: 1),
        GitDiffLine(kind: .removed, text: "line two", oldNumber: 2, newNumber: nil),
        GitDiffLine(kind: .added, text: "line two changed", oldNumber: nil, newNumber: 2),
        GitDiffLine(kind: .added, text: "line two point five", oldNumber: nil, newNumber: 3),
        GitDiffLine(kind: .context, text: "line three", oldNumber: 3, newNumber: 4),
      ]
    )
    #expect(
      diff.hunks[1].lines == [
        GitDiffLine(kind: .context, text: "ctx", oldNumber: 10, newNumber: 11),
        GitDiffLine(kind: .removed, text: "removed", oldNumber: 11, newNumber: nil),
        GitDiffLine(kind: .added, text: "added", oldNumber: nil, newNumber: 12),
      ]
    )
  }

  @Test func parsesHunkHeaderWithOmittedCounts() {
    let output = """
      --- a/f
      +++ b/f
      @@ -3 +3 @@
      -old
      +new
      """

    let diff = GitClient.parseFileDiff(output)

    #expect(
      diff.hunks.first?.lines == [
        GitDiffLine(kind: .removed, text: "old", oldNumber: 3, newNumber: nil),
        GitDiffLine(kind: .added, text: "new", oldNumber: nil, newNumber: 3),
      ]
    )
  }

  @Test func flagsBinaryDiff() {
    let output = """
      diff --git a/img.png b/img.png
      index 1234567..89abcde 100644
      Binary files a/img.png and b/img.png differ
      """

    let diff = GitClient.parseFileDiff(output)

    #expect(diff.isBinary)
    #expect(diff.hunks.isEmpty)
  }

  @Test func emptyOutputParsesToEmptyDiff() {
    let diff = GitClient.parseFileDiff("")

    #expect(!diff.isBinary)
    #expect(diff.hunks.isEmpty)
  }

  @Test func renameOnlyDiffHasNoHunks() {
    let output = """
      diff --git a/Old.swift b/New.swift
      similarity index 100%
      rename from Old.swift
      rename to New.swift
      """

    let diff = GitClient.parseFileDiff(output)

    #expect(!diff.isBinary)
    #expect(diff.hunks.isEmpty)
  }

  @Test func skipsNoNewlineMarker() {
    let output = """
      --- a/f
      +++ b/f
      @@ -1 +1 @@
      -old
      \\ No newline at end of file
      +new
      \\ No newline at end of file
      """

    let diff = GitClient.parseFileDiff(output)

    #expect(
      diff.hunks.first?.lines == [
        GitDiffLine(kind: .removed, text: "old", oldNumber: 1, newNumber: nil),
        GitDiffLine(kind: .added, text: "new", oldNumber: nil, newNumber: 1),
      ]
    )
  }

  @Test func preservesLeadingWhitespaceInLineText() {
    let output = """
      --- a/f
      +++ b/f
      @@ -1 +1 @@
      -  indented old
      +    indented new
      """

    let diff = GitClient.parseFileDiff(output)

    #expect(diff.hunks.first?.lines[0].text == "  indented old")
    #expect(diff.hunks.first?.lines[1].text == "    indented new")
  }
}
