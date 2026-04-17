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
  case webFallbackNotAvailable

  var errorDescription: String? {
    switch self {
    case .publisherURLNotFound:
      return "Could not find a publisher URL in the Apple News page."
    case .webFallbackNotAvailable:
      return
        "Apple News page does not expose a publisher URL; article appears to be app-only or unavailable on the web."
    }
  }
}

func resolutionErrorDescription(_ error: Error) -> String {
  let metadata = resolutionErrorMetadata(error)
  let message =
    if let localizedError = error as? any LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      description
    } else {
      error.localizedDescription
    }

  guard !metadata.isEmpty else {
    return message
  }

  return "\(message) [\(metadata.joined(separator: " "))]"
}

private func resolutionErrorMetadata(_ error: Error) -> [String] {
  switch error {
  case let pageError as AppleNewsPageFetchingError:
    switch pageError {
    case .unsuccessfulStatusCode(let statusCode, _):
      return ["http_status=\(statusCode)"]
    case .invalidResponse:
      return ["error_code=invalid_response"]
    }
  case AppleNewsPublisherURLExtractionError.publisherURLNotFound:
    return ["error_code=publisher_url_not_found"]
  case AppleNewsPublisherURLExtractionError.webFallbackNotAvailable:
    return ["error_code=web_fallback_not_available"]
  case let urlError as URLError:
    return [
      "domain=\(NSURLErrorDomain)",
      "code=\(urlError.errorCode)",
      "url_error=\(urlErrorName(urlError.code))",
    ]
  default:
    let nsError = error as NSError
    return [
      "domain=\(nsError.domain)",
      "code=\(nsError.code)",
    ]
  }
}

private func urlErrorName(_ code: URLError.Code) -> String {
  switch code {
  case .timedOut:
    return "timedOut"
  case .cannotFindHost:
    return "cannotFindHost"
  case .cannotConnectToHost:
    return "cannotConnectToHost"
  case .networkConnectionLost:
    return "networkConnectionLost"
  case .dnsLookupFailed:
    return "dnsLookupFailed"
  case .notConnectedToInternet:
    return "notConnectedToInternet"
  case .secureConnectionFailed:
    return "secureConnectionFailed"
  case .badServerResponse:
    return "badServerResponse"
  case .resourceUnavailable:
    return "resourceUnavailable"
  case .appTransportSecurityRequiresSecureConnection:
    return "appTransportSecurityRequiresSecureConnection"
  case .cannotParseResponse:
    return "cannotParseResponse"
  default:
    return "rawValue:\(code.rawValue)"
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

    if html.contains("It may also be available on the publisher") {
      throw AppleNewsPublisherURLExtractionError.webFallbackNotAvailable
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
