import Foundation
import SQLite3
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

private func createSQLiteDatabase(
  at url: URL,
  statements: [String]
) throws {
  var database: OpaquePointer?
  guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
    throw TestError.missingMockResponse
  }
  defer { sqlite3_close(database) }

  for statement in statements {
    guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
      throw TestError.missingMockResponse
    }
  }
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
func appleNewsReferencesCanBeBuiltFromIDs() throws {
  let reference = try AppleNewsArticleReference(id: "AgYBtZhCLTD2ZCmgVQI1g6w")

  #expect(reference.id == "AgYBtZhCLTD2ZCmgVQI1g6w")
  #expect(
    reference.url.absoluteString == "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w"
  )
}

@Test
func appleNewsReferencesPreferHTTPS() throws {
  let reference = try AppleNewsArticleReference(
    url: #require(URL(string: "http://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w"))
  )

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
func swiftDataStoreBatchUpsertsMappings() throws {
  let store = try ArticleMappings(location: .inMemory)
  let mappings = try [
    ArticleMapping(
      appleNews: AppleNewsArticleReference(id: "AgYBtZhCLTD2ZCmgVQI1g6w"),
      publisher: PublisherArticleReference(
        url: #require(
          URL(
            string:
              "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
          )
        )
      )
    ),
    ArticleMapping(
      appleNews: AppleNewsArticleReference(id: "AE6VqukUiTbWVl_629NVnlA"),
      publisher: PublisherArticleReference(
        url: #require(
          URL(
            string:
              "https://www.theverge.com/news/679946/apple-rejected-court-attempt-to-stop-app-store-web-links"
          )
        )
      )
    ),
  ]

  try store.upsertAll(mappings)

  #expect(try store.mappingCount() == 2)
  #expect(
    try store.allMappings().map(\.id).sorted() == [
      "AE6VqukUiTbWVl_629NVnlA",
      "AgYBtZhCLTD2ZCmgVQI1g6w",
    ]
  )
}

@Test
func swiftDataStorePersistsDiscoveriesIndependentlyOfMappings() throws {
  let store = try ArticleMappings(location: .inMemory)
  let articles = try [
    AppleNewsArticleReference(id: "AgYBtZhCLTD2ZCmgVQI1g6w"),
    AppleNewsArticleReference(id: "AE6VqukUiTbWVl_629NVnlA"),
  ]

  try store.upsertDiscoveries(articles)

  #expect(
    try store.recentDiscoveries(limit: 10).map(\.id).sorted() == [
      "AE6VqukUiTbWVl_629NVnlA",
      "AgYBtZhCLTD2ZCmgVQI1g6w",
    ]
  )
}

@Test
func swiftDataStoreAddsMappedArticlesToDiscoveryList() throws {
  let store = try ArticleMappings(location: .inMemory)
  let mapping = try ArticleMapping(
    appleNews: AppleNewsArticleReference(id: "AgYBtZhCLTD2ZCmgVQI1g6w"),
    publisher: PublisherArticleReference(
      url: #require(
        URL(
          string:
            "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
        )
      )
    )
  )

  try store.upsert(mapping)

  #expect(
    try store.recentDiscoveries(limit: 10).map(\.id) == [
      "AgYBtZhCLTD2ZCmgVQI1g6w"
    ]
  )
}

@Test
func swiftDataStoreBuildsRecentDiscoveryListItems() throws {
  let store = try ArticleMappings(location: .inMemory)
  let mappedArticle = try AppleNewsArticleReference(
    id: "AgYBtZhCLTD2ZCmgVQI1g6w"
  )
  let unmappedArticle = try AppleNewsArticleReference(
    id: "AE6VqukUiTbWVl_629NVnlA"
  )

  try store.upsert(
    ArticleMapping(
      appleNews: mappedArticle,
      publisher: PublisherArticleReference(
        url: #require(
          URL(
            string:
              "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
          )
        )
      )
    )
  )
  try store.upsertDiscoveries([mappedArticle, unmappedArticle])

  let items = try store.recentDiscoveryItems(limit: 10).map(\.description)

  #expect(items.contains("https://apple.news/AE6VqukUiTbWVl_629NVnlA"))
  #expect(
    items.contains(
      "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w -> https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
    )
  )
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

@Test
func headlineArchiveExtractorFindsFirstPublisherURL() throws {
  let archive = Data(
    [
      0x00,
      0xFF,
    ]
      + Array(
        """
        https://apple.news/PwUAzN8gHXeVyBRdor7WHib
        \u{0}
        https://c.apple.news/P/1/Afoo/imgfile?a=123
        \u{0}
        https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming?utm_source=test
        \u{0}
        https://subscribe.latimes.com/assets/awan.html
        """.utf8
      )
  )

  let publisher = try HeadlineArchivePublisherURLExtractor()
    .publisherReference(in: archive)

  #expect(
    publisher.url.absoluteString
      == "https://www.latimes.com/california/story/2026-04-13/la-county-budget-upcoming"
  )
}

@Test
func localAppleNewsReferenceExtractorFindsDirectURLsAndArticleIDs() throws {
  let data = Data(
    """
    https:\\/\\/apple.news\\/AgYBtZhCLTD2ZCmgVQI1g6w?subscribe=1\u{0}articleID\u{0}AE6VqukUiTbWVl_629NVnlA\u{0}sourceChannelID\u{0}Th81kyFuPRHWdFPaWOKGYNQ\u{0}https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w\u{0}https://apple.news/Th81kyFuPRHWdFPaWOKGYNQ\u{0}https://apple.news/magazines
    """.utf8
  )

  let references = LocalAppleNewsReferenceExtractor().articleReferences(
    in: data
  )

  #expect(
    references.map(\.id) == [
      "AgYBtZhCLTD2ZCmgVQI1g6w",
      "AE6VqukUiTbWVl_629NVnlA",
    ]
  )
}

@Test
func binaryStringExtractorCanReadNthPrintableToken() {
  let data = Data(
    [0x02]
      + Array("feed$en-US".utf8)
      + [0x0A]
      + Array("AgYBtZhCLTD2ZCmgVQI1g6w".utf8)
      + [0x10]
      + Array("Ttopic123".utf8)
  )

  #expect(
    BinaryStringExtractor().string(in: data, at: 1)
      == "AgYBtZhCLTD2ZCmgVQI1g6w"
  )
}

@Test
func localReferralEntryMappingExtractorBuildsMappingsFromEntryJSON() throws {
  let archive = Data(
    """
    https://apple.news/PwUAzN8gHXeVyBRdor7WHib\u{0}https://www.theverge.com/news/679946/apple-rejected-court-attempt-to-stop-app-store-web-links\u{0}
    """.utf8
  ).base64EncodedString()
  let entry = """
    {
      "content": {
        "sections": [
          {
            "items": [
              {
                "headline": {
                  "actionUrl": "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w?widgetModeGroupID=0",
                  "ntHeadlineData": "\(archive)"
                }
              },
              {
                "headline": {
                  "actionUrl": "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w?duplicate=1",
                  "ntHeadlineData": "\(archive)"
                }
              }
            ]
          }
        ]
      }
    }
    """

  let mappings = try LocalReferralEntryMappingExtractor().mappings(
    inEntryData: Data(entry.utf8)
  )

  #expect(mappings.count == 1)
  #expect(mappings[0].appleNews.id == "AgYBtZhCLTD2ZCmgVQI1g6w")
  #expect(
    mappings[0].publisher.url.absoluteString
      == "https://www.theverge.com/news/679946/apple-rejected-court-attempt-to-stop-app-store-web-links"
  )
}

@Test
func localAppleNewsDatabaseReferenceDiscovererFindsArticleIDsAcrossStores()
  throws
{
  let directory = URL.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  defer { try? FileManager.default.removeItem(at: directory) }

  let articleExposuresURL = directory.appending(path: "article_exposures")
  let feedDatabaseURL = directory.appending(path: "feeddatabase")
  let todayFeedDatabaseURL = directory.appending(path: "today-feed-db")

  try createSQLiteDatabase(
    at: articleExposuresURL,
    statements: [
      """
      CREATE TABLE ItemExposure (
        id TEXT NOT NULL,
        FirstExposedAt DOUBLE NOT NULL,
        LastExposedAt DOUBLE NOT NULL,
        MaxExposedVersion INTEGER NOT NULL,
        MaxExposedVersionFirstExposedAt DOUBLE NOT NULL,
        LastAccessedAt DOUBLE NOT NULL,
        PRIMARY KEY (id)
      );
      """,
      """
      INSERT INTO ItemExposure
        (id, FirstExposedAt, LastExposedAt, MaxExposedVersion, MaxExposedVersionFirstExposedAt, LastAccessedAt)
      VALUES
        ('AgYBtZhCLTD2ZCmgVQI1g6w', 1, 1, 1, 1, 1);
      """,
    ]
  )

  try createSQLiteDatabase(
    at: feedDatabaseURL,
    statements: [
      "CREATE TABLE feed_item (id INTEGER PRIMARY KEY, encoded BLOB);",
      """
      INSERT INTO feed_item (id, encoded)
      VALUES (1, 'articleID AE6VqukUiTbWVl_629NVnlA');
      """,
    ]
  )

  try createSQLiteDatabase(
    at: todayFeedDatabaseURL,
    statements: [
      "CREATE TABLE blobs (id TEXT NOT NULL, cursorId TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY (id));",
      "CREATE TABLE groups (id TEXT NOT NULL, itemIds BLOB NOT NULL, PRIMARY KEY (id));",
      "CREATE TABLE group_trackers (id TEXT NOT NULL, itemIds BLOB NOT NULL, PRIMARY KEY (id));",
      """
      INSERT INTO blobs (id, cursorId, data)
      VALUES ('g.data-1', 'cursor-1', '{"headline":"https://apple.news/PwUAzN8gHXeVyBRdor7WHib"}');
      """,
      """
      INSERT INTO groups (id, itemIds)
      VALUES ('group-1', 'A_6VwCGGySoKYEfdv-zzVeg');
      """,
      """
      INSERT INTO group_trackers (id, itemIds)
      VALUES ('tracker-1', 'A4oE6S2NWRDyZfW1_VRBaPg');
      """,
    ]
  )

  let discoverer = LocalAppleNewsDatabaseReferenceDiscoverer(
    databaseURLs: LocalAppleNewsDatabaseURLs(
      articleExposuresURL: articleExposuresURL,
      feedDatabaseURL: feedDatabaseURL,
      todayFeedDatabaseURL: todayFeedDatabaseURL
    ),
    cache: nil
  )

  let ids = Set(discoverer.articleReferences().map(\.id))

  #expect(ids.contains("AgYBtZhCLTD2ZCmgVQI1g6w"))
  #expect(ids.contains("AE6VqukUiTbWVl_629NVnlA"))
  #expect(ids.contains("PwUAzN8gHXeVyBRdor7WHib"))
  #expect(ids.contains("A_6VwCGGySoKYEfdv-zzVeg"))
  #expect(ids.contains("A4oE6S2NWRDyZfW1_VRBaPg"))
}

@Test
func localAppleNewsDatabaseReferenceCacheInvalidatesWhenSourceFilesChange()
  throws
{
  let directory = URL.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  defer { try? FileManager.default.removeItem(at: directory) }

  let articleExposuresURL = directory.appending(path: "article_exposures")
  let feedDatabaseURL = directory.appending(path: "feeddatabase")
  let todayFeedDatabaseURL = directory.appending(path: "today-feed-db")
  let cacheURL = directory.appending(path: "protected-store-cache.json")

  try createSQLiteDatabase(
    at: articleExposuresURL,
    statements: [
      """
      CREATE TABLE ItemExposure (
        id TEXT NOT NULL,
        FirstExposedAt DOUBLE NOT NULL,
        LastExposedAt DOUBLE NOT NULL,
        MaxExposedVersion INTEGER NOT NULL,
        MaxExposedVersionFirstExposedAt DOUBLE NOT NULL,
        LastAccessedAt DOUBLE NOT NULL,
        PRIMARY KEY (id)
      );
      """
    ]
  )

  let databaseURLs = LocalAppleNewsDatabaseURLs(
    articleExposuresURL: articleExposuresURL,
    feedDatabaseURL: feedDatabaseURL,
    todayFeedDatabaseURL: todayFeedDatabaseURL
  )
  let cache = LocalAppleNewsDatabaseReferenceCache(fileURL: cacheURL)
  let references = try [
    AppleNewsArticleReference(id: "AgYBtZhCLTD2ZCmgVQI1g6w")
  ]

  cache.save(references, for: databaseURLs)

  #expect(
    cache.articleReferences(for: databaseURLs)?.map(\.id) == [
      "AgYBtZhCLTD2ZCmgVQI1g6w"
    ]
  )

  try Data("changed".utf8).write(to: feedDatabaseURL)

  #expect(cache.articleReferences(for: databaseURLs) == nil)
}

@Test
func localAppleNewsDiscoveryOnlyScansFilesWhenRequested() throws {
  let directory = URL.temporaryDirectory.appending(
    path: UUID().uuidString,
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  defer { try? FileManager.default.removeItem(at: directory) }

  let referralItemsURL = directory.appending(
    path: "referralItems",
    directoryHint: .isDirectory
  )
  let referralItemDirectory = referralItemsURL.appending(
    path: "item-1",
    directoryHint: .isDirectory
  )
  let scanRootURL = directory.appending(
    path: "scan-root",
    directoryHint: .isDirectory
  )
  let articleExposuresURL = directory.appending(path: "article_exposures")

  try FileManager.default.createDirectory(
    at: referralItemDirectory,
    withIntermediateDirectories: true
  )
  try FileManager.default.createDirectory(
    at: scanRootURL,
    withIntermediateDirectories: true
  )

  let archive = Data(
    """
    https://apple.news/PwUAzN8gHXeVyBRdor7WHib\u{0}https://www.theverge.com/news/679946/apple-rejected-court-attempt-to-stop-app-store-web-links\u{0}
    """.utf8
  ).base64EncodedString()
  let entry = """
    {
      "content": {
        "sections": [
          {
            "items": [
              {
                "headline": {
                  "actionUrl": "https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w",
                  "ntHeadlineData": "\(archive)"
                }
              }
            ]
          }
        ]
      }
    }
    """

  try Data(entry.utf8).write(
    to: referralItemDirectory.appending(path: "entry")
  )
  try Data("https://apple.news/PQ6l8CQu_j5qqdTdZfptvyw".utf8).write(
    to: scanRootURL.appending(path: "payload.bin")
  )

  try createSQLiteDatabase(
    at: articleExposuresURL,
    statements: [
      """
      CREATE TABLE ItemExposure (
        id TEXT NOT NULL,
        FirstExposedAt DOUBLE NOT NULL,
        LastExposedAt DOUBLE NOT NULL,
        MaxExposedVersion INTEGER NOT NULL,
        MaxExposedVersionFirstExposedAt DOUBLE NOT NULL,
        LastAccessedAt DOUBLE NOT NULL,
        PRIMARY KEY (id)
      );
      """,
      """
      INSERT INTO ItemExposure
        (id, FirstExposedAt, LastExposedAt, MaxExposedVersion, MaxExposedVersionFirstExposedAt, LastAccessedAt)
      VALUES
        ('AgYBtZhCLTD2ZCmgVQI1g6w', 1, 1, 1, 1, 1),
        ('AE6VqukUiTbWVl_629NVnlA', 1, 1, 1, 1, 1);
      """,
    ]
  )

  let discovery = LocalAppleNewsDiscovery(
    databaseDiscoverer: LocalAppleNewsDatabaseReferenceDiscoverer(
      databaseURLs: LocalAppleNewsDatabaseURLs(
        articleExposuresURL: articleExposuresURL,
        feedDatabaseURL: directory.appending(path: "missing-feeddatabase"),
        todayFeedDatabaseURL: directory.appending(path: "missing-today-feed-db")
      ),
      cache: nil
    )
  )

  let defaultResult = try discovery.discover(
    referralItemsURL: referralItemsURL,
    searchRootURLs: [scanRootURL]
  )
  let exhaustiveResult = try discovery.discover(
    referralItemsURL: referralItemsURL,
    searchRootURLs: [scanRootURL],
    includeFileScan: true
  )

  #expect(defaultResult.mappings.map(\.id) == ["AgYBtZhCLTD2ZCmgVQI1g6w"])
  #expect(
    defaultResult.articleReferences.map(\.id) == ["AE6VqukUiTbWVl_629NVnlA"]
  )
  #expect(
    exhaustiveResult.articleReferences.map(\.id) == [
      "AE6VqukUiTbWVl_629NVnlA",
      "PQ6l8CQu_j5qqdTdZfptvyw",
    ]
  )
}
