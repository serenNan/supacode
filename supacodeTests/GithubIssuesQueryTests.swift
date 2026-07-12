import Testing

@testable import supacode

struct GithubIssuesQueryTests {
  @Test func queryRequestsOpenIssuesByRecency() {
    let query = GithubIssuesQuery.query
    #expect(query.contains("issues(first: 50, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC})"))
    #expect(query.contains("repository(owner: $owner, name: $repo)"))
    #expect(query.contains("comments {"))
    #expect(query.contains("totalCount"))
    #expect(query.contains("labels(first: 10)"))
  }
}
