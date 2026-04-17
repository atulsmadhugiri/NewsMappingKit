import Foundation

package enum BlueskySearchDefaults {
  package static let query = "apple.news"
  package static let limit = 25
  package static let maxPages = 100
  package static let pageSize = 100
}

package enum BlueskySearchError: LocalizedError {
  case invalidResponse(URL)
  case unsuccessfulStatusCode(Int, URL)

  package var errorDescription: String? {
    switch self {
    case .invalidResponse(let url):
      return "Expected an HTTP response for \(url.absoluteString)."
    case .unsuccessfulStatusCode(let statusCode, let url):
      return "Received HTTP \(statusCode) while fetching \(url.absoluteString)."
    }
  }
}

package struct BlueskyCredentials: Encodable, Sendable {
  package let identifier: String
  package let appPassword: String

  package init(identifier: String, appPassword: String) {
    self.identifier = identifier
    self.appPassword = appPassword
  }

  private enum CodingKeys: String, CodingKey {
    case identifier
    case appPassword = "password"
  }
}

private struct BlueskySession: Decodable, Sendable {
  let accessJwt: String
}

private struct BlueskySearchPage: Decodable, Sendable {
  let cursor: String?
}

package struct BlueskySearchDiscoverer: Sendable {
  private static let defaultUnauthenticatedAPIBaseURL = URL(
    string: "https://api.bsky.app"
  )!
  private static let defaultAuthenticatedAPIBaseURL = URL(
    string: "https://bsky.social"
  )!

  let unauthenticatedAPIBaseURL: URL
  let authenticatedAPIBaseURL: URL
  let client: any HTTPClient
  let extractor: LocalAppleNewsReferenceExtractor

  package init(
    unauthenticatedAPIBaseURL: URL = defaultUnauthenticatedAPIBaseURL,
    authenticatedAPIBaseURL: URL = defaultAuthenticatedAPIBaseURL,
    client: some HTTPClient = URLSessionHTTPClient(),
    extractor: LocalAppleNewsReferenceExtractor =
      LocalAppleNewsReferenceExtractor()
  ) {
    self.unauthenticatedAPIBaseURL = unauthenticatedAPIBaseURL
    self.authenticatedAPIBaseURL = authenticatedAPIBaseURL
    self.client = client
    self.extractor = extractor
  }

  package func articleReferences(
    query: String = BlueskySearchDefaults.query,
    limit: Int = BlueskySearchDefaults.limit,
    maxPages: Int = BlueskySearchDefaults.maxPages,
    credentials: BlueskyCredentials? = nil,
    progress: ProgressHandler? = nil
  ) async throws -> [AppleNewsArticleReference] {
    guard limit > 0, maxPages > 0 else {
      return []
    }

    let accessToken = try await accessToken(
      for: credentials,
      progress: progress
    )
    let apiBaseURL =
      accessToken == nil
      ? unauthenticatedAPIBaseURL
      : authenticatedAPIBaseURL

    var results = [AppleNewsArticleReference]()
    var seenIDs = Set<String>()
    var seenCursors = Set<String>()
    var cursor: String?
    var pageCount = 0

    while pageCount < maxPages, results.count < limit {
      let remainingCount = limit - results.count
      let pageSize = min(BlueskySearchDefaults.pageSize, remainingCount)
      let (page, data) = try await searchPage(
        apiBaseURL: apiBaseURL,
        query: query,
        limit: pageSize,
        cursor: cursor,
        accessToken: accessToken
      )
      pageCount += 1

      let newReferences = extractor.articleReferences(in: data).filter {
        seenIDs.insert($0.id).inserted
      }
      results.append(
        contentsOf: newReferences.prefix(limit - results.count)
      )

      progress?(
        "Fetched Bluesky page \(pageCount) (\(results.count.formatted())/\(limit.formatted()) unique Apple News URLs)."
      )

      guard
        let nextCursor = page.cursor,
        !nextCursor.isEmpty,
        seenCursors.insert(nextCursor).inserted
      else {
        break
      }

      cursor = nextCursor
    }

    return results
  }

  private func searchPage(
    apiBaseURL: URL,
    query: String,
    limit: Int,
    cursor: String?,
    accessToken: String?
  ) async throws -> (BlueskySearchPage, Data) {
    let url = searchURL(
      apiBaseURL: apiBaseURL,
      query: query,
      limit: limit,
      cursor: cursor
    )
    var request = URLRequest(url: url)
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let accessToken {
      request.setValue(
        "Bearer \(accessToken)",
        forHTTPHeaderField: "Authorization"
      )
    }

    let data = try await data(for: request)
    return (try JSONDecoder().decode(BlueskySearchPage.self, from: data), data)
  }

  private func accessToken(
    for credentials: BlueskyCredentials?,
    progress: ProgressHandler?
  ) async throws -> String? {
    guard let credentials else {
      return nil
    }

    progress?("Authenticating with Bluesky...")
    return try await createSession(credentials).accessJwt
  }

  private func createSession(_ credentials: BlueskyCredentials) async throws
    -> BlueskySession
  {
    let url = authenticatedAPIBaseURL.appending(
      path: "xrpc/com.atproto.server.createSession",
      directoryHint: .notDirectory
    )
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try JSONEncoder().encode(credentials)

    let data = try await data(for: request)
    return try JSONDecoder().decode(BlueskySession.self, from: data)
  }

  private func data(for request: URLRequest) async throws -> Data {
    let (data, response) = try await client.data(for: request)
    guard let url = request.url else {
      return data
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw BlueskySearchError.invalidResponse(url)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw BlueskySearchError.unsuccessfulStatusCode(
        httpResponse.statusCode,
        url
      )
    }

    return data
  }

  private func searchURL(
    apiBaseURL: URL,
    query: String,
    limit: Int,
    cursor: String?
  ) -> URL {
    var components = URLComponents(
      url: apiBaseURL,
      resolvingAgainstBaseURL: false
    )!
    components.path = "/xrpc/app.bsky.feed.searchPosts"
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "sort", value: "latest"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]

    if let cursor {
      components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
    }

    return components.url!
  }
}
