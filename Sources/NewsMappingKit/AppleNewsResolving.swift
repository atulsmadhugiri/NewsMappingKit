import Foundation

enum AppleNewsPageFetchingError: LocalizedError {
  case invalidResponse(URL)
  case unsuccessfulStatusCode(Int, URL)

  var errorDescription: String? {
    switch self {
    case .invalidResponse(let url):
      return "Expected an HTTP response for \(url.absoluteString)."
    case .unsuccessfulStatusCode(let statusCode, let url):
      return "Received HTTP \(statusCode) while fetching \(url.absoluteString)."
    }
  }
}

enum AppleNewsPublisherURLExtractionError: LocalizedError {
  case publisherURLNotFound

  var errorDescription: String? {
    switch self {
    case .publisherURLNotFound:
      return "Could not find a publisher URL in the Apple News page."
    }
  }
}

struct AppleNewsPageFetcher: Sendable {
  private let client: any HTTPClient

  init(client: some HTTPClient = URLSessionHTTPClient()) {
    self.client = client
  }

  func fetchHTML(for article: AppleNewsArticleReference) async throws -> String
  {
    var request = URLRequest(url: article.url)
    request.timeoutInterval = 30
    request.setValue("text/html", forHTTPHeaderField: "Accept")

    let (data, response) = try await client.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AppleNewsPageFetchingError.invalidResponse(article.url)
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      throw AppleNewsPageFetchingError.unsuccessfulStatusCode(
        httpResponse.statusCode,
        article.url
      )
    }

    return String(decoding: data, as: UTF8.self)
  }
}

struct AppleNewsPublisherURLExtractor: Sendable {
  func publisherReference(in html: String) throws -> PublisherArticleReference {
    for candidate in [
      firstMatch(of: #/redirectToUrl(?:AfterTimeout)?\("([^"]+)"/#, in: html),
      firstMatch(of: #/<a href="([^"]+)"><span class="click-here">/#, in: html),
    ] {
      guard let candidate,
        let url = URL(string: candidate),
        let reference = try? PublisherArticleReference(url: url)
      else {
        continue
      }

      return reference
    }

    throw AppleNewsPublisherURLExtractionError.publisherURLNotFound
  }

  private func firstMatch(
    of pattern: Regex<(Substring, Substring)>,
    in html: String
  ) -> String? {
    html.firstMatch(of: pattern).map { String($0.1) }
  }
}

struct AppleNewsMappingResolver: Sendable {
  let fetcher: AppleNewsPageFetcher
  let extractor: AppleNewsPublisherURLExtractor

  init(
    fetcher: AppleNewsPageFetcher = AppleNewsPageFetcher(),
    extractor: AppleNewsPublisherURLExtractor = AppleNewsPublisherURLExtractor()
  ) {
    self.fetcher = fetcher
    self.extractor = extractor
  }

  func resolve(_ article: AppleNewsArticleReference) async throws
    -> ArticleMapping
  {
    let html = try await fetcher.fetchHTML(for: article)
    let publisher = try extractor.publisherReference(in: html)
    return ArticleMapping(appleNews: article, publisher: publisher)
  }
}
