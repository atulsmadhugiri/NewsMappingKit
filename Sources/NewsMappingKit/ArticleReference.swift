import ArgumentParser
import Foundation

private let appleNewsHost = "apple.news"

enum ArticleReferenceError: LocalizedError {
  case invalidURL(String)
  case missingHost(URL)
  case invalidAppleNewsHost(URL)
  case missingAppleNewsIdentifier(URL)
  case publisherURLUsesAppleNewsHost(URL)

  var errorDescription: String? {
    switch self {
    case .invalidURL(let argument):
      return "Invalid URL: \(argument)"
    case .missingHost(let url):
      return "URL must include a host: \(url.absoluteString)"
    case .invalidAppleNewsHost(let url):
      return
        "Apple News URLs must use the apple.news host: \(url.absoluteString)"
    case .missingAppleNewsIdentifier(let url):
      return
        "Apple News URLs must contain an article identifier in the path: \(url.absoluteString)"
    case .publisherURLUsesAppleNewsHost(let url):
      return
        "Publisher URLs cannot use the apple.news host: \(url.absoluteString)"
    }
  }
}

private protocol URLArgumentConvertible: ExpressibleByArgument {
  init(url: URL) throws
}

extension URLArgumentConvertible {
  init?(argument: String) {
    guard let url = URL(string: argument),
      let reference = try? Self(url: url)
    else {
      return nil
    }

    self = reference
  }
}

struct AppleNewsArticleReference: Hashable, Codable, Sendable,
  CustomStringConvertible, URLArgumentConvertible
{
  let id: String
  let url: URL

  init(url: URL) throws {
    let canonicalURL = try url.canonicalizedForMapping()

    guard canonicalURL.host?.lowercased() == appleNewsHost else {
      throw ArticleReferenceError.invalidAppleNewsHost(canonicalURL)
    }

    let id = canonicalURL.lastPathComponent.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !id.isEmpty, id != "/" else {
      throw ArticleReferenceError.missingAppleNewsIdentifier(canonicalURL)
    }

    self.id = id
    self.url = canonicalURL
  }

  var description: String {
    url.absoluteString
  }
}

struct PublisherArticleReference: Hashable, Codable, Sendable,
  CustomStringConvertible, URLArgumentConvertible
{
  let url: URL

  init(url: URL) throws {
    let canonicalURL = try url.canonicalizedForMapping()

    guard let host = canonicalURL.host else {
      throw ArticleReferenceError.missingHost(canonicalURL)
    }

    guard host.lowercased() != appleNewsHost else {
      throw ArticleReferenceError.publisherURLUsesAppleNewsHost(canonicalURL)
    }

    self.url = canonicalURL
  }

  var description: String {
    url.absoluteString
  }
}

extension URL {
  fileprivate func canonicalizedForMapping() throws -> URL {
    guard
      var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
    else {
      throw ArticleReferenceError.invalidURL(absoluteString)
    }

    guard let scheme = components.scheme,
      let host = components.host
    else {
      throw ArticleReferenceError.missingHost(self)
    }

    components.scheme = scheme.lowercased()
    components.host = host.lowercased()
    components.fragment = nil
    components.query = nil

    if let port = components.port,
      Self.isDefaultPort(port, scheme: components.scheme)
    {
      components.port = nil
    }

    if components.path.count > 1, components.path.hasSuffix("/") {
      components.path.removeLast()
    }

    guard let canonicalURL = components.url else {
      throw ArticleReferenceError.invalidURL(absoluteString)
    }

    return canonicalURL
  }

  private static func isDefaultPort(_ port: Int, scheme: String?) -> Bool {
    switch scheme?.lowercased() {
    case "http":
      return port == 80
    case "https":
      return port == 443
    default:
      return false
    }
  }
}
