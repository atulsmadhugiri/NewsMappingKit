import Foundation

public protocol HTTPClient: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public enum HTTPClientConfiguration {
  public static let maximumConnectionsPerHost = 64
}

public struct URLSessionHTTPClient: HTTPClient {
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpMaximumConnectionsPerHost =
      HTTPClientConfiguration.maximumConnectionsPerHost
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration)
  }()

  public init() {}

  public func data(for request: URLRequest) async throws
    -> (Data, URLResponse)
  {
    try await Self.session.data(for: request)
  }
}
