import Foundation
import Testing

@testable import SupacodeSettingsShared
@testable import supacode

private let unit = "\u{1f}"
private let record = "\u{1e}"

actor CommitHistoryShellCallStore {
  private(set) var calls: [[String]] = []

  func record(_ arguments: [String]) {
    calls.append(arguments)
  }
}

struct GitClientParseCommitLogTests {
  private func logLine(
    hash: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    shortHash: String = "aaaaaaa",
    author: String = "Alice",
    date: String = "2026-07-11T10:00:00+08:00",
    decorations: String = "",
    subject: String = "feat: something"
  ) -> String {
    [hash, shortHash, author, date, decorations, subject].joined(separator: unit) + record + "\n"
  }

  @Test func parsesMultipleRecordsInOrder() throws {
    let output =
      logLine(hash: String(repeating: "a", count: 40), shortHash: "aaaaaaa", subject: "feat: first")
      + logLine(hash: String(repeating: "b", count: 40), shortHash: "bbbbbbb", subject: "fix: second")

    let commits = GitClient.parseCommitLog(output)

    #expect(commits.count == 2)
    #expect(commits[0].hash == String(repeating: "a", count: 40))
    #expect(commits[0].shortHash == "aaaaaaa")
    #expect(commits[0].subject == "feat: first")
    #expect(commits[1].subject == "fix: second")
    #expect(commits[0].author == "Alice")
  }

  @Test func parsesAuthorDateAsISO8601() throws {
    let output = logLine(date: "2026-07-11T10:00:00+08:00")

    let commits = GitClient.parseCommitLog(output)

    let expected = try Date("2026-07-11T10:00:00+08:00", strategy: .iso8601)
    #expect(commits.first?.date == expected)
  }

  @Test func parsesHeadBranchDecoration() {
    let output = logLine(
      decorations: "HEAD -> refs/heads/main, refs/remotes/origin/main"
    )

    let refs = GitClient.parseCommitLog(output).first?.refs ?? []

    #expect(
      refs == [
        GitCommitRef(name: "main", kind: .localBranch, isHead: true),
        GitCommitRef(name: "origin/main", kind: .remoteBranch, isHead: false),
      ]
    )
  }

  @Test func parsesTagDecoration() {
    let output = logLine(decorations: "tag: refs/tags/v1.0")

    let refs = GitClient.parseCommitLog(output).first?.refs ?? []

    #expect(refs == [GitCommitRef(name: "v1.0", kind: .tag, isHead: false)])
  }

  @Test func parsesDetachedHeadDecoration() {
    let output = logLine(decorations: "HEAD")

    let refs = GitClient.parseCommitLog(output).first?.refs ?? []

    #expect(refs == [GitCommitRef(name: "HEAD", kind: .detachedHead, isHead: true)])
  }

  @Test func emptyDecorationsYieldNoRefs() {
    let output = logLine(decorations: "")

    let commits = GitClient.parseCommitLog(output)

    #expect(commits.first?.refs.isEmpty == true)
  }

  @Test func parsesEmojiAndUnicodeFields() {
    let output = logLine(author: "张三", subject: "feat: 加个 git 树 🌳")

    let commits = GitClient.parseCommitLog(output)

    #expect(commits.first?.author == "张三")
    #expect(commits.first?.subject == "feat: 加个 git 树 🌳")
  }

  @Test func emptyOutputYieldsNoCommits() {
    #expect(GitClient.parseCommitLog("").isEmpty)
    #expect(GitClient.parseCommitLog("\n").isEmpty)
  }

  @Test func skipsMalformedRecords() {
    let output = "garbage-without-separators" + record + "\n" + logLine(subject: "fix: valid")

    let commits = GitClient.parseCommitLog(output)

    #expect(commits.count == 1)
    #expect(commits.first?.subject == "fix: valid")
  }
}

struct GitClientParseCommitDetailTests {
  private let hash = String(repeating: "c", count: 40)

  private func showOutput(body: String, numstat: String) -> String {
    [hash, "Alice", "alice@example.com", "2026-07-11T10:00:00+08:00", body]
      .joined(separator: unit) + record + "\n" + numstat
  }

  @Test func parsesHeaderAndMultilineBody() {
    let body = "feat: subject line\n\n加个正文，带 emoji 🌳。\nSecond body line.\n"
    let output = showOutput(body: body, numstat: "3\t1\tsupacode/App/ContentView.swift\n")

    let detail = GitClient.parseCommitDetail(output)

    #expect(detail?.hash == hash)
    #expect(detail?.author == "Alice")
    #expect(detail?.email == "alice@example.com")
    #expect(detail?.message == "feat: subject line\n\n加个正文，带 emoji 🌳。\nSecond body line.")
  }

  @Test func parsesNumstatFiles() {
    let numstat = "12\t3\tsupacode/App/A.swift\n0\t7\tsupacodeTests/B.swift\n"
    let output = showOutput(body: "subject", numstat: numstat)

    let files = GitClient.parseCommitDetail(output)?.files ?? []

    #expect(
      files == [
        GitCommitFileChange(path: "supacode/App/A.swift", added: 12, removed: 3),
        GitCommitFileChange(path: "supacodeTests/B.swift", added: 0, removed: 7),
      ]
    )
  }

  @Test func binaryFilesHaveNilCounts() {
    let output = showOutput(body: "subject", numstat: "-\t-\tAssets/icon.png\n")

    let files = GitClient.parseCommitDetail(output)?.files ?? []

    #expect(files == [GitCommitFileChange(path: "Assets/icon.png", added: nil, removed: nil)])
  }

  @Test func renamedPathsAreKeptVerbatim() {
    let output = showOutput(body: "subject", numstat: "1\t1\tsupacode/{Old => New}/File.swift\n")

    let files = GitClient.parseCommitDetail(output)?.files ?? []

    #expect(files.first?.path == "supacode/{Old => New}/File.swift")
  }

  @Test func commitWithNoFilesHasEmptyList() {
    let output = showOutput(body: "empty commit", numstat: "")

    let detail = GitClient.parseCommitDetail(output)

    #expect(detail != nil)
    #expect(detail?.files.isEmpty == true)
  }

  @Test func malformedOutputReturnsNil() {
    #expect(GitClient.parseCommitDetail("") == nil)
    #expect(GitClient.parseCommitDetail("not-a-show-output") == nil)
  }
}

struct GitClientCommitHistoryTests {
  private func logRecord(hash: Character, subject: String, decorations: String = "") -> String {
    [
      String(repeating: hash, count: 40),
      String(repeating: hash, count: 7),
      "Alice",
      "2026-07-11T10:00:00+08:00",
      decorations,
      subject,
    ].joined(separator: unit) + "\u{1e}" + "\n"
  }

  @Test func commitHistoryRunsLogUpstreamAndAheadCount() async throws {
    let store = CommitHistoryShellCallStore()
    let logOutput =
      logRecord(hash: "a", subject: "feat: newest", decorations: "HEAD -> refs/heads/main")
      + logRecord(hash: "b", subject: "fix: older", decorations: "refs/remotes/origin/main")
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        if arguments.contains("log") {
          return ShellOutput(stdout: logOutput, stderr: "", exitCode: 0)
        }
        if arguments.contains("rev-parse") {
          return ShellOutput(stdout: "origin/main\n", stderr: "", exitCode: 0)
        }
        if arguments.contains("rev-list") {
          return ShellOutput(stdout: "1\n", stderr: "", exitCode: 0)
        }
        return ShellOutput(stdout: "", stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let snapshot = try await client.commitHistory(at: URL(fileURLWithPath: "/tmp/repo"), limit: 200)

    #expect(snapshot.commits.count == 2)
    #expect(snapshot.upstreamRef == "origin/main")
    #expect(snapshot.aheadCount == 1)
    #expect(snapshot.isTruncated == false)

    let calls = await store.calls
    let logCall = calls.first { $0.contains("log") }
    #expect(logCall != nil)
    #expect(logCall?.contains("--first-parent") == true)
    #expect(logCall?.contains("-n") == true)
    #expect(logCall?.contains("200") == true)
    #expect(logCall?.contains("--decorate=full") == true)
    let aheadCall = calls.first { $0.contains("rev-list") }
    #expect(aheadCall?.contains("--count") == true)
    #expect(aheadCall?.contains("@{upstream}..HEAD") == true)
  }

  @Test func missingUpstreamYieldsZeroAhead() async throws {
    let logOutput = logRecord(hash: "a", subject: "feat: only")
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("log") {
          return ShellOutput(stdout: logOutput, stderr: "", exitCode: 0)
        }
        throw GitClientError.commandFailed(command: "git", message: "no upstream configured")
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let snapshot = try await client.commitHistory(at: URL(fileURLWithPath: "/tmp/repo"), limit: 200)

    #expect(snapshot.upstreamRef == nil)
    #expect(snapshot.aheadCount == 0)
  }

  @Test func truncationFlagSetWhenLimitReached() async throws {
    let logOutput = logRecord(hash: "a", subject: "one") + logRecord(hash: "b", subject: "two")
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("log") {
          return ShellOutput(stdout: logOutput, stderr: "", exitCode: 0)
        }
        throw GitClientError.commandFailed(command: "git", message: "no upstream")
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let snapshot = try await client.commitHistory(at: URL(fileURLWithPath: "/tmp/repo"), limit: 2)

    #expect(snapshot.isTruncated == true)
  }

  @Test func unbornRepositoryYieldsEmptyHistory() async throws {
    let shell = ShellClient(
      run: { _, arguments, _ in
        if arguments.contains("--is-inside-work-tree") {
          return ShellOutput(stdout: "true\n", stderr: "", exitCode: 0)
        }
        throw GitClientError.commandFailed(
          command: "git", message: "does not have any commits yet")
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let snapshot = try await client.commitHistory(at: URL(fileURLWithPath: "/tmp/repo"), limit: 200)

    #expect(snapshot.commits.isEmpty)
    #expect(snapshot.aheadCount == 0)
    #expect(snapshot.isTruncated == false)
  }

  @Test func logFailureThrows() async {
    let shell = ShellClient(
      run: { _, _, _ in
        throw GitClientError.commandFailed(command: "git log", message: "not a repository")
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    await #expect(throws: (any Error).self) {
      _ = try await client.commitHistory(at: URL(fileURLWithPath: "/tmp/repo"), limit: 200)
    }
  }

  @Test func commitDetailRunsGitShowNumstat() async throws {
    let store = CommitHistoryShellCallStore()
    let hash = String(repeating: "c", count: 40)
    let showOutput =
      [hash, "Alice", "alice@example.com", "2026-07-11T10:00:00+08:00", "subject"]
      .joined(separator: unit) + "\u{1e}" + "\n" + "1\t2\tREADME.md\n"
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        return ShellOutput(stdout: showOutput, stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let detail = try await client.commitDetail(at: URL(fileURLWithPath: "/tmp/repo"), hash: hash)

    #expect(detail.hash == hash)
    #expect(detail.files == [GitCommitFileChange(path: "README.md", added: 1, removed: 2)])
    let calls = await store.calls
    let showCall = calls.first { $0.contains("show") }
    #expect(showCall?.contains(hash) == true)
    #expect(showCall?.contains("--numstat") == true)
  }

  @Test func uncommittedChangesRunsDiffNumstat() async throws {
    let store = CommitHistoryShellCallStore()
    let output = "12\t3\tsupacode/App/A.swift\n-\t-\tAssets/icon.png\n"
    let shell = ShellClient(
      run: { _, arguments, _ in
        await store.record(arguments)
        return ShellOutput(stdout: output, stderr: "", exitCode: 0)
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    let files = try await client.uncommittedChanges(at: URL(fileURLWithPath: "/tmp/repo"))

    #expect(
      files == [
        GitCommitFileChange(path: "supacode/App/A.swift", added: 12, removed: 3),
        GitCommitFileChange(path: "Assets/icon.png", added: nil, removed: nil),
      ]
    )
    let calls = await store.calls
    let diffCall = calls.first { $0.contains("diff") }
    #expect(diffCall?.contains("HEAD") == true)
    #expect(diffCall?.contains("--numstat") == true)
  }
}

struct GitClientFileDiffTests {
  private nonisolated static let diffOutput = """
    diff --git a/supacode/App/A.swift b/supacode/App/A.swift
    index 1234567..89abcde 100644
    --- a/supacode/App/A.swift
    +++ b/supacode/App/A.swift
    @@ -1 +1 @@
    -old
    +new
    """

  private func client(recording store: CommitHistoryShellCallStore) -> GitClient {
    GitClient(
      shell: ShellClient(
        run: { _, arguments, _ in
          await store.record(arguments)
          return ShellOutput(stdout: Self.diffOutput, stderr: "", exitCode: 0)
        },
        runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
      )
    )
  }

  @Test func uncommittedFileDiffRunsGitDiffHeadScopedToPath() async throws {
    let store = CommitHistoryShellCallStore()

    let diff = try await client(recording: store).uncommittedFileDiff(
      at: URL(fileURLWithPath: "/tmp/repo"), path: "supacode/App/A.swift")

    #expect(diff.hunks.count == 1)
    #expect(diff.hunks.first?.lines.count == 2)
    let call = await store.calls.first
    #expect(call?.contains("diff") == true)
    #expect(call?.contains("HEAD") == true)
    #expect(call?.contains("--") == true)
    #expect(call?.contains("supacode/App/A.swift") == true)
  }

  @Test func commitFileDiffRunsGitShowPatchScopedToPath() async throws {
    let store = CommitHistoryShellCallStore()
    let hash = String(repeating: "d", count: 40)

    let diff = try await client(recording: store).commitFileDiff(
      at: URL(fileURLWithPath: "/tmp/repo"), hash: hash, path: "supacode/App/A.swift")

    #expect(diff.hunks.count == 1)
    let call = await store.calls.first
    #expect(call?.contains("show") == true)
    #expect(call?.contains("--format=") == true)
    #expect(call?.contains("--patch") == true)
    #expect(call?.contains(hash) == true)
    #expect(call?.contains("--") == true)
    #expect(call?.contains("supacode/App/A.swift") == true)
  }

  @Test func fileDiffFailureThrows() async {
    let shell = ShellClient(
      run: { _, _, _ in
        throw GitClientError.commandFailed(command: "git diff", message: "boom")
      },
      runLoginImpl: { _, _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) }
    )
    let client = GitClient(shell: shell)

    await #expect(throws: (any Error).self) {
      _ = try await client.uncommittedFileDiff(
        at: URL(fileURLWithPath: "/tmp/repo"), path: "A.swift")
    }
    await #expect(throws: (any Error).self) {
      _ = try await client.commitFileDiff(
        at: URL(fileURLWithPath: "/tmp/repo"), hash: "abc", path: "A.swift")
    }
  }
}
