import Foundation
import Testing

@testable import supacode

struct TerminalFileReferenceTests {
  private let root = URL(filePath: "/repo")

  private func resolve(
    _ clicked: String,
    pwd: String? = "/repo",
    existing: Set<String>
  ) -> TerminalFileReference? {
    TerminalFileReference.resolve(
      clicked: clicked,
      pwd: pwd,
      worktreeRoot: root,
      fileExists: { existing.contains($0) }
    )
  }

  @Test func relativePathWithLine() {
    let reference = resolve(
      "supacode/Foo.swift:123",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: 123))
  }

  @Test func relativePathWithLineAndColumn() {
    let reference = resolve(
      "src/main.swift:10:5",
      existing: ["/repo/src/main.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "src/main.swift", line: 10))
  }

  @Test func barePathWithoutLine() {
    let reference = resolve(
      "supacode/Foo.swift",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: nil))
  }

  @Test func absolutePathInsideWorktree() {
    let reference = resolve(
      "/repo/supacode/Foo.swift:7",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: 7))
  }

  @Test func exactFilenameContainingColonWins() {
    let reference = resolve(
      "notes.txt:12",
      existing: ["/repo/notes.txt:12", "/repo/notes.txt"]
    )
    #expect(reference == TerminalFileReference(relativePath: "notes.txt:12", line: nil))
  }

  @Test func relativePathResolvedAgainstPwdSubdirectory() {
    let reference = resolve(
      "Views/Bar.swift:3",
      pwd: "/repo/supacode",
      existing: ["/repo/supacode/Views/Bar.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Views/Bar.swift", line: 3))
  }

  @Test func missingPwdFallsBackToWorktreeRoot() {
    let reference = resolve(
      "supacode/Foo.swift:9",
      pwd: nil,
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: 9))
  }

  @Test func dotRelativePathNormalized() {
    let reference = resolve(
      "./supacode/Foo.swift:4",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: 4))
  }

  @Test func parentTraversalStaysInsideWorktree() {
    let reference = resolve(
      "../supacode/Foo.swift:2",
      pwd: "/repo/supacodeTests",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: 2))
  }

  @Test func fileURIResolves() {
    let reference = resolve(
      "file:///repo/supacode/Foo.swift",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: nil))
  }

  @Test func httpSchemeDoesNotResolve() {
    let reference = resolve(
      "https://example.com/foo.swift",
      existing: ["/repo/foo.swift"]
    )
    #expect(reference == nil)
  }

  @Test func fileOutsideWorktreeDoesNotResolve() {
    let reference = resolve(
      "/etc/hosts",
      existing: ["/etc/hosts"]
    )
    #expect(reference == nil)
  }

  @Test func siblingDirectorySharingPrefixDoesNotResolve() {
    let reference = resolve(
      "/repo-other/Foo.swift",
      existing: ["/repo-other/Foo.swift"]
    )
    #expect(reference == nil)
  }

  @Test func worktreeRootItselfDoesNotResolve() {
    let reference = resolve(
      "/repo",
      existing: ["/repo"]
    )
    #expect(reference == nil)
  }

  @Test func nonexistentFileDoesNotResolve() {
    let reference = resolve(
      "supacode/Missing.swift:5",
      existing: []
    )
    #expect(reference == nil)
  }

  @Test func zeroLineTreatedAsNoLine() {
    let reference = resolve(
      "supacode/Foo.swift:0",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: nil))
  }

  @Test func trailingWhitespaceTrimmed() {
    let reference = resolve(
      " supacode/Foo.swift:123 ",
      existing: ["/repo/supacode/Foo.swift"]
    )
    #expect(reference == TerminalFileReference(relativePath: "supacode/Foo.swift", line: 123))
  }

  @Test(arguments: [
    "output/screenshot.png", "docs/spec.PDF", "assets/logo.JPeG", "clip.mp4",
    "song.mp3", "release.zip", "报告.docx", "icon.icns",
  ])
  func mediaAndBinaryExtensionsPreferSystemOpen(path: String) {
    #expect(TerminalFileReference(relativePath: path, line: nil).prefersSystemOpen)
  }

  @Test(arguments: [
    "supacode/Foo.swift", "README.md", "Makefile", "config.json", "notes.txt",
    "script.sh", "src/url.zig",
  ])
  func textualFilesDoNotPreferSystemOpen(path: String) {
    #expect(!TerminalFileReference(relativePath: path, line: nil).prefersSystemOpen)
  }
}
