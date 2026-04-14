import Foundation
import Testing

@testable import NewsMappingKit

private struct MockHTTPClient: HTTPClient {
  let responses: [URL: String]

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    guard let url = request.url, let response = responses[url] else {
      throw TestError.missingMockResponse
    }

    let httpResponse = try #require(
      HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )
    )

    return (Data(response.utf8), httpResponse)
  }
}

private enum TestError: Error {
  case missingMockResponse
}

@Test
func appleNewsReferencesAreCanonicalized() throws {
  let reference = try AppleNewsArticleReference(
    url: #require(
      URL(
        string:
          "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w/?utm_source=test#fragment"
      )
    )
  )

  #expect(reference.id == "AgYBtZhCLTD2ZCmgVQI1g6w")
  #expect(
    reference.url.absoluteString == "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w"
  )
}

@Test
func swiftDataStoreRoundTripsMappings() throws {
  let store = try ArticleMappings(location: .inMemory)
  let appleNews = try AppleNewsArticleReference(
    url: #require(URL(string: "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w"))
  )
  let publisher = try PublisherArticleReference(
    url: #require(
      URL(
        string:
          "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming?utm_source=test#fragment"
      )
    )
  )

  try store.upsert(ArticleMapping(appleNews: appleNews, publisher: publisher))

  let publisherLookup = try #require(
    try store.mapping(forAppleNews: appleNews)
  )
  let appleNewsLookup = try #require(
    try store.mapping(forPublisher: publisher)
  )

  #expect(
    publisherLookup.publisher.url.absoluteString
      == "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
  )
  #expect(appleNewsLookup.appleNews.id == appleNews.id)
}

@Test
func publisherURLExtractorFindsRedirectURL() throws {
  let html = """
    <script>
      redirectToUrl("https://www.theverge.com/news/679946/apple-rejected-court-attempt-to-stop-app-store-web-links");
    </script>
    """

  let publisher = try AppleNewsPublisherURLExtractor().publisherReference(
    in: html
  )

  #expect(
    publisher.url.absoluteString
      == "https://www.theverge.com/news/679946/apple-rejected-court-attempt-to-stop-app-store-web-links"
  )
}

@Test
func publisherURLExtractorFallsBackToClickHereLink() throws {
  let html = """
    <p><a href="https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"><span class="click-here">Click here</span></a></p>
    """

  let publisher = try AppleNewsPublisherURLExtractor().publisherReference(
    in: html
  )

  #expect(
    publisher.url.absoluteString
      == "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
  )
}

@Test
func appleNewsResolverBuildsMappingFromFetchedHTML() async throws {
  let appleNews = try AppleNewsArticleReference(
    url: #require(URL(string: "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w"))
  )
  let html = """
    <script>
      redirectToUrl("https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming");
    </script>
    """
  let resolver = AppleNewsMappingResolver(
    fetcher: AppleNewsPageFetcher(
      client: MockHTTPClient(responses: [appleNews.url: html])
    )
  )

  let mapping = try await resolver.resolve(appleNews)

  #expect(mapping.appleNews == appleNews)
  #expect(
    mapping.publisher.url.absoluteString
      == "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
  )
}
