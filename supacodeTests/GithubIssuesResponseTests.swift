import Foundation
import Testing

@testable import supacode

struct GithubIssuesResponseTests {
  @Test func decodesAllAndInvolvedSetsWithState() throws {
    let json = """
      {
        "data": {
          "repository": {
            "issues": {
              "nodes": [
                {
                  "number": 630,
                  "title": "Clamp notification body",
                  "url": "https://github.com/octo/repo/issues/630",
                  "updatedAt": "2026-07-11T06:03:02Z",
                  "state": "OPEN",
                  "author": { "login": "serenNan" },
                  "labels": {
                    "nodes": [
                      { "name": "enhancement", "color": "a2eeef" }
                    ]
                  },
                  "comments": { "totalCount": 3 }
                },
                {
                  "number": 629,
                  "title": "Localization support",
                  "url": "https://github.com/octo/repo/issues/629",
                  "updatedAt": "2026-07-11T02:57:51Z",
                  "state": "OPEN",
                  "author": null,
                  "labels": { "nodes": [] },
                  "comments": { "totalCount": 0 }
                }
              ]
            }
          },
          "search": {
            "nodes": [
              {
                "number": 700,
                "title": "You were mentioned",
                "url": "https://github.com/octo/repo/issues/700",
                "updatedAt": "2026-07-12T00:00:00Z",
                "state": "CLOSED",
                "author": { "login": "someone" },
                "labels": { "nodes": [] },
                "comments": { "totalCount": 1 }
              }
            ]
          }
        }
      }
      """
    let response = try Self.decode(json)

    let all = response.allIssues
    #expect(all.count == 2)
    let first = try #require(all.first)
    #expect(first.number == 630)
    #expect(first.title == "Clamp notification body")
    #expect(first.authorLogin == "serenNan")
    #expect(first.labels == [GithubIssueLabel(name: "enhancement", color: "a2eeef")])
    #expect(first.commentsCount == 3)
    #expect(first.isClosed == false)
    #expect(try #require(all.last).authorLogin == nil)

    let involved = response.involvedIssues
    #expect(involved.count == 1)
    let mine = try #require(involved.first)
    #expect(mine.number == 700)
    #expect(mine.authorLogin == "someone")
    #expect(mine.commentsCount == 1)
    #expect(mine.isClosed == true)
  }

  @Test func involvedSetEmptyWhenSearchBlockAbsent() throws {
    // The no-login query omits the search block entirely.
    let json = """
      {
        "data": {
          "repository": {
            "issues": {
              "nodes": [
                {
                  "number": 1,
                  "title": "Only open issues",
                  "url": "https://github.com/octo/repo/issues/1",
                  "updatedAt": null,
                  "state": "OPEN",
                  "author": { "login": "octo" },
                  "labels": { "nodes": [] },
                  "comments": { "totalCount": 0 }
                }
              ]
            }
          }
        }
      }
      """
    let response = try Self.decode(json)
    #expect(response.allIssues.count == 1)
    #expect(response.involvedIssues.isEmpty)
  }

  @Test func queryOmitsSearchWithoutLogin() {
    let query = GithubIssuesQuery.query(includeInvolved: false)
    #expect(!query.contains("search("))
    #expect(!query.contains("searchQuery"))
  }

  @Test func queryIncludesSearchWithLogin() {
    let query = GithubIssuesQuery.query(includeInvolved: true)
    #expect(query.contains("search(query: $searchQuery, type: ISSUE"))
    #expect(query.contains("$searchQuery: String!"))
  }

  @Test func involvesSearchQueryScopesToRepoAndLogin() {
    let search = GithubIssuesQuery.involvesSearchQuery(owner: "octo", repo: "repo", login: "serenNan")
    #expect(search == "repo:octo/repo is:issue involves:serenNan sort:updated-desc")
  }

  private static func decode(_ json: String) throws -> GithubIssuesGraphQLResponse {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(GithubIssuesGraphQLResponse.self, from: Data(json.utf8))
  }
}
