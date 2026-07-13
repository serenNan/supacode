import Foundation

nonisolated enum GithubIssuesQuery {
  // The issue fields selected in both the repository `issues` connection (the
  // "All" set) and the top-level `search` connection (the "Mine" set).
  private static let issueFields = """
    number
    title
    url
    updatedAt
    state
    stateReason
    author {
      login
    }
    labels(first: 10) {
      nodes {
        name
        color
      }
    }
    comments {
      totalCount
    }
    """

  /// Combined query. `repository.issues` feeds the All list; when
  /// `includeInvolved` is true a `$searchQuery` variable drives a `search`
  /// connection feeding the Mine list and notifications — one round trip for
  /// both. Omit the search block when there is no signed-in login to scope by.
  static func query(includeInvolved: Bool) -> String {
    let variables = includeInvolved
      ? "$owner: String!, $repo: String!, $searchQuery: String!"
      : "$owner: String!, $repo: String!"
    let searchBlock = includeInvolved
      ? """

          search(query: $searchQuery, type: ISSUE, first: 50) {
            nodes {
              ... on Issue {
                \(issueFields)
              }
            }
          }
        """
      : ""
    return """
      query(\(variables)) {
        repository(owner: $owner, name: $repo) {
          issues(first: 50, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
            nodes {
              \(issueFields)
            }
          }
        }\(searchBlock)
      }
      """
  }

  /// The `search` query string bound to `$searchQuery`: every issue the login is
  /// involved in (author / assignee / mentioned / commenter), most-recent first,
  /// open and closed.
  static func involvesSearchQuery(owner: String, repo: String, login: String) -> String {
    "repo:\(owner)/\(repo) is:issue involves:\(login) sort:updated-desc"
  }
}

nonisolated struct GithubIssuesGraphQLResponse: Decodable {
  let data: DataContainer

  /// Repository open issues (the All list). Empty when the block is absent.
  var allIssues: [GithubIssue] {
    data.repository?.issues.nodes.map(\.issue) ?? []
  }

  /// Issues the signed-in login is involved in (the Mine list + notifications).
  /// Empty when the query omitted the search block (no login).
  var involvedIssues: [GithubIssue] {
    data.search?.nodes.map(\.issue) ?? []
  }

  nonisolated struct DataContainer: Decodable {
    let repository: Repository?
    let search: NodeConnection?
  }

  nonisolated struct Repository: Decodable {
    let issues: NodeConnection
  }

  nonisolated struct NodeConnection: Decodable {
    let nodes: [IssueNode]
  }

  nonisolated struct IssueNode: Decodable {
    let number: Int
    let title: String
    let url: String
    let updatedAt: Date?
    let state: String?
    let stateReason: String?
    let author: IssueAuthor?
    let labels: LabelConnection
    let comments: CommentConnection

    var issue: GithubIssue {
      GithubIssue(
        number: number,
        title: title,
        url: url,
        updatedAt: updatedAt,
        authorLogin: author?.login,
        labels: labels.nodes,
        commentsCount: comments.totalCount,
        isClosed: state == "CLOSED",
        stateReason: stateReason
      )
    }
  }

  nonisolated struct IssueAuthor: Decodable {
    let login: String
  }

  nonisolated struct LabelConnection: Decodable {
    let nodes: [GithubIssueLabel]
  }

  nonisolated struct CommentConnection: Decodable {
    let totalCount: Int
  }
}
