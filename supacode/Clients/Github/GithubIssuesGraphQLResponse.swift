import Foundation

nonisolated enum GithubIssuesQuery {
  static let query = """
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        issues(first: 50, states: [OPEN], orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes {
            number
            title
            url
            updatedAt
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
          }
        }
      }
    }
    """
}

nonisolated struct GithubIssuesGraphQLResponse: Decodable {
  let data: DataContainer

  var issues: [GithubIssue] {
    data.repository.issues.nodes.map(\.issue)
  }

  nonisolated struct DataContainer: Decodable {
    let repository: Repository
  }

  nonisolated struct Repository: Decodable {
    let issues: IssueConnection
  }

  nonisolated struct IssueConnection: Decodable {
    let nodes: [IssueNode]
  }

  nonisolated struct IssueNode: Decodable {
    let number: Int
    let title: String
    let url: String
    let updatedAt: Date?
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
        commentsCount: comments.totalCount
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
