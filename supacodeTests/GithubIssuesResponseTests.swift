import Foundation
import Testing

@testable import supacode

struct GithubIssuesResponseTests {
  @Test func decodesIssuesFromGraphQLResponse() throws {
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
                  "author": null,
                  "labels": { "nodes": [] },
                  "comments": { "totalCount": 0 }
                }
              ]
            }
          }
        }
      }
      """
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(GithubIssuesGraphQLResponse.self, from: data)
    let issues = response.issues
    #expect(issues.count == 2)
    let first = try #require(issues.first)
    #expect(first.number == 630)
    #expect(first.title == "Clamp notification body")
    #expect(first.url == "https://github.com/octo/repo/issues/630")
    #expect(first.authorLogin == "serenNan")
    #expect(first.labels == [GithubIssueLabel(name: "enhancement", color: "a2eeef")])
    #expect(first.commentsCount == 3)
    #expect(first.id == 630)
    let second = try #require(issues.last)
    #expect(second.authorLogin == nil)
    #expect(second.labels.isEmpty)
    #expect(second.commentsCount == 0)
  }
}
