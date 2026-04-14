import Foundation
import SQLite3

enum LocalAppleNewsDiscoveryError: LocalizedError {
  case invalidReferralItemsDirectory(URL)
  case publisherURLNotFound

  var errorDescription: String? {
    switch self {
    case .invalidReferralItemsDirectory(let url):
      return
        "Referral items directory does not exist or is not a directory: \(url.path)"
    case .publisherURLNotFound:
      return "Could not find a publisher URL in the local headline archive."
    }
  }
}

enum LocalAppleNewsPaths {
  static let referralItemsURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(
      path:
        "Library/News/com.apple.news.public-com.apple.news.private-production/referralItems",
      directoryHint: .isDirectory
    )

  static let newsStorageURL = referralItemsURL.deletingLastPathComponent()

  static let newsContainerURL = FileManager.default.homeDirectoryForCurrentUser
    .appending(
      path: "Library/Containers/com.apple.news",
      directoryHint: .isDirectory
    )

  static let newsCacheURL = newsContainerURL.appending(
    path: "Data/Library/Caches/News/com.apple.news.public-production-143441",
    directoryHint: .isDirectory
  )

  static let articleExposuresURL = FileManager.default
    .homeDirectoryForCurrentUser
    .appending(
      path:
        "Library/Group Containers/group.com.apple.news/com.apple.news.public-com.apple.news.private-production/article_exposures",
      directoryHint: .notDirectory
    )

  static let feedDatabaseURL = newsCacheURL.appending(
    path: "feeddatabase",
    directoryHint: .notDirectory
  )

  static let todayFeedDatabaseURL = newsCacheURL.appending(
    path: "today-feed-db",
    directoryHint: .notDirectory
  )

  static let protectedStoreReferenceCacheURL = URL.applicationSupportDirectory
    .appending(path: "NewsMappingKit", directoryHint: .isDirectory)
    .appending(
      path: "LocalAppleNewsProtectedStoreReferences.json",
      directoryHint: .notDirectory
    )

  static let defaultSearchRootURLs = [
    newsStorageURL,
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Caches/com.apple.newsd",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/HTTPStorages/com.apple.newsd",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Group Containers/group.com.apple.news",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Group Containers/group.com.apple.newsd",
      directoryHint: .isDirectory
    ),
    newsContainerURL,
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Containers/com.apple.news.tag",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Containers/com.apple.news.widget",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Containers/com.apple.news.widgetintents",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Containers/com.apple.news.engagementExtension",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Containers/com.apple.news.openinnews",
      directoryHint: .isDirectory
    ),
    FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Containers/com.apple.news.articlenotificationextension",
      directoryHint: .isDirectory
    ),
  ]
}

struct LocalDiscoveryFileFinder: Sendable {
  func regularFiles(in rootURLs: [URL]) -> [URL] {
    var results = [URL]()
    var seenPaths = Set<String>()

    for rootURL in rootURLs {
      for fileURL in regularFiles(in: rootURL)
      where seenPaths.insert(fileURL.path).inserted {
        results.append(fileURL)
      }
    }

    return results
  }

  func entryFiles(in rootURL: URL) throws -> [URL] {
    var isDirectory = ObjCBool(false)
    guard
      FileManager.default.fileExists(
        atPath: rootURL.path,
        isDirectory: &isDirectory
      ), isDirectory.boolValue
    else {
      throw LocalAppleNewsDiscoveryError.invalidReferralItemsDirectory(rootURL)
    }

    return regularFiles(in: [rootURL]).filter {
      $0.lastPathComponent == "entry"
    }
  }

  private func regularFiles(in rootURL: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return
      enumerator
      .compactMap { $0 as? URL }
      .filter(Self.isRegularFile)
  }

  private static func isRegularFile(_ url: URL) -> Bool {
    do {
      return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile
        == true
    } catch {
      return false
    }
  }
}

struct LocalAppleNewsDatabaseURLs: Sendable {
  let articleExposuresURL: URL
  let feedDatabaseURL: URL
  let todayFeedDatabaseURL: URL

  static let live = LocalAppleNewsDatabaseURLs(
    articleExposuresURL: LocalAppleNewsPaths.articleExposuresURL,
    feedDatabaseURL: LocalAppleNewsPaths.feedDatabaseURL,
    todayFeedDatabaseURL: LocalAppleNewsPaths.todayFeedDatabaseURL
  )
}

private struct LocalAppleNewsDatabaseSnapshot: Codable, Equatable, Sendable {
  let path: String
  let exists: Bool
  let fileSize: Int64?
  let modificationDate: Date?

  init(url: URL) {
    path = url.path

    guard FileManager.default.fileExists(atPath: url.path) else {
      exists = false
      fileSize = nil
      modificationDate = nil
      return
    }

    let values = try? url.resourceValues(
      forKeys: [.fileSizeKey, .contentModificationDateKey]
    )
    exists = true
    fileSize = values?.fileSize.map(Int64.init)
    modificationDate = values?.contentModificationDate
  }
}

private struct LocalAppleNewsDatabaseReferenceCacheRecord: Codable, Sendable {
  let articleExposuresSnapshot: LocalAppleNewsDatabaseSnapshot
  let feedDatabaseSnapshot: LocalAppleNewsDatabaseSnapshot
  let todayFeedDatabaseSnapshot: LocalAppleNewsDatabaseSnapshot
  let articleIDs: [String]
}

struct LocalAppleNewsDatabaseReferenceCache: Sendable {
  let fileURL: URL

  static let live = LocalAppleNewsDatabaseReferenceCache(
    fileURL: LocalAppleNewsPaths.protectedStoreReferenceCacheURL
  )

  func articleReferences(for databaseURLs: LocalAppleNewsDatabaseURLs)
    -> [AppleNewsArticleReference]?
  {
    guard
      let record = loadRecord(),
      record.articleExposuresSnapshot
        == LocalAppleNewsDatabaseSnapshot(
          url: databaseURLs.articleExposuresURL
        ),
      record.feedDatabaseSnapshot
        == LocalAppleNewsDatabaseSnapshot(
          url: databaseURLs.feedDatabaseURL
        ),
      record.todayFeedDatabaseSnapshot
        == LocalAppleNewsDatabaseSnapshot(
          url: databaseURLs.todayFeedDatabaseURL
        )
    else {
      return nil
    }

    return record.articleIDs.compactMap {
      try? AppleNewsArticleReference(id: $0)
    }
  }

  func save(
    _ references: [AppleNewsArticleReference],
    for databaseURLs: LocalAppleNewsDatabaseURLs
  ) {
    let record = LocalAppleNewsDatabaseReferenceCacheRecord(
      articleExposuresSnapshot: LocalAppleNewsDatabaseSnapshot(
        url: databaseURLs.articleExposuresURL
      ),
      feedDatabaseSnapshot: LocalAppleNewsDatabaseSnapshot(
        url: databaseURLs.feedDatabaseURL
      ),
      todayFeedDatabaseSnapshot: LocalAppleNewsDatabaseSnapshot(
        url: databaseURLs.todayFeedDatabaseURL
      ),
      articleIDs: references.map(\.id)
    )

    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let data = try encoder.encode(record)
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      return
    }
  }

  private func loadRecord() -> LocalAppleNewsDatabaseReferenceCacheRecord? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }

    do {
      let data = try Data(contentsOf: fileURL)
      return try JSONDecoder().decode(
        LocalAppleNewsDatabaseReferenceCacheRecord.self,
        from: data
      )
    } catch {
      return nil
    }
  }
}

struct LocalReferralEntry: Decodable, Sendable {
  let content: Content

  var headlines: [Headline] {
    content.sections.flatMap(\.items).compactMap(\.headline)
  }

  struct Content: Decodable, Sendable {
    let sections: [Section]
  }

  struct Section: Decodable, Sendable {
    let items: [Item]
  }

  struct Item: Decodable, Sendable {
    let headline: Headline?
  }

  struct Headline: Decodable, Sendable {
    let actionURL: URL?
    let headlineArchive: Data?

    private enum CodingKeys: String, CodingKey {
      case actionURL = "actionUrl"
      case headlineArchive = "ntHeadlineData"
    }
  }
}

struct BinaryStringExtractor: Sendable {
  var minimumLength = 8

  func strings(in data: Data) -> [String] {
    data
      .split(whereSeparator: { !(32...126).contains($0) })
      .lazy
      .filter { $0.count >= minimumLength }
      .map { String(decoding: $0, as: UTF8.self) }
  }

  func string(in data: Data, at ordinal: Int) -> String? {
    guard ordinal >= 0 else {
      return nil
    }

    var currentOrdinal = 0
    var startIndex: Data.Index?

    for index in data.indices {
      let byte = data[index]

      if (32...126).contains(byte) {
        if startIndex == nil {
          startIndex = index
        }
        continue
      }

      if let match = matchedString(
        in: data,
        startIndex: startIndex,
        endIndex: index,
        currentOrdinal: &currentOrdinal,
        targetOrdinal: ordinal
      ) {
        return match
      }

      startIndex = nil
    }

    return matchedString(
      in: data,
      startIndex: startIndex,
      endIndex: data.endIndex,
      currentOrdinal: &currentOrdinal,
      targetOrdinal: ordinal
    )
  }

  private func matchedString(
    in data: Data,
    startIndex: Data.Index?,
    endIndex: Data.Index,
    currentOrdinal: inout Int,
    targetOrdinal: Int
  ) -> String? {
    guard let startIndex else {
      return nil
    }

    let length = data.distance(from: startIndex, to: endIndex)
    guard length >= minimumLength else {
      return nil
    }

    defer { currentOrdinal += 1 }

    guard currentOrdinal == targetOrdinal else {
      return nil
    }

    return String(decoding: data[startIndex..<endIndex], as: UTF8.self)
  }
}

struct LocalAppleNewsReferenceExtractor: Sendable {
  let stringExtractor: BinaryStringExtractor

  init(stringExtractor: BinaryStringExtractor = BinaryStringExtractor()) {
    self.stringExtractor = stringExtractor
  }

  func articleReferences(in data: Data) -> [AppleNewsArticleReference] {
    let fragments = normalizedFragments(in: data)
    var results = [AppleNewsArticleReference]()
    var seenIDs = Set<String>()

    for fragment in fragments {
      append(
        embeddedURLReferences(in: fragment),
        to: &results,
        seenIDs: &seenIDs
      )
      append(
        inlineArticleIDReferences(in: fragment),
        to: &results,
        seenIDs: &seenIDs
      )
      append(
        standaloneArticleIDReferences(in: fragment),
        to: &results,
        seenIDs: &seenIDs
      )
    }

    for (key, value) in zip(fragments, fragments.dropFirst())
    where Self.articleIDKeys.contains(Self.normalizedKey(key)) {
      append(
        [articleReference(forID: value)].compactMap(\.self),
        to: &results,
        seenIDs: &seenIDs
      )
    }

    return results
  }

  private func normalizedFragments(in data: Data) -> [String] {
    stringExtractor.strings(in: data).map(Self.normalizedFragment)
  }

  private func embeddedURLReferences(in fragment: String)
    -> [AppleNewsArticleReference]
  {
    fragment.matches(of: appleNewsURLPattern).compactMap { match in
      guard
        let url = URL(string: Self.sanitizedURLString(String(match.output))),
        let reference = try? AppleNewsArticleReference(url: url),
        Self.isLikelyArticleID(reference.id)
      else {
        return nil
      }

      return reference
    }
  }

  private func inlineArticleIDReferences(in fragment: String)
    -> [AppleNewsArticleReference]
  {
    fragment.matches(of: inlineArticleIDPattern).compactMap { match in
      articleReference(forID: String(match.1))
    }
  }

  private func standaloneArticleIDReferences(in fragment: String)
    -> [AppleNewsArticleReference]
  {
    let range = NSRange(fragment.startIndex..<fragment.endIndex, in: fragment)

    return Self.standaloneArticleIDRegex.matches(in: fragment, range: range)
      .compactMap { match in
        guard let range = Range(match.range, in: fragment) else {
          return nil
        }

        return articleReference(forID: String(fragment[range]))
      }
  }

  private func articleReference(forID value: String)
    -> AppleNewsArticleReference?
  {
    guard
      let reference = try? AppleNewsArticleReference(
        id: Self.sanitizedIdentifier(value)
      ),
      Self.isLikelyArticleID(reference.id)
    else {
      return nil
    }

    return reference
  }

  private func append(
    _ references: [AppleNewsArticleReference],
    to results: inout [AppleNewsArticleReference],
    seenIDs: inout Set<String>
  ) {
    for reference in references where seenIDs.insert(reference.id).inserted {
      results.append(reference)
    }
  }

  private static func normalizedFragment(_ fragment: String) -> String {
    fragment
      .replacingOccurrences(of: #"\/"#, with: "/")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func normalizedKey(_ fragment: String) -> String {
    fragment.trimmingCharacters(
      in: CharacterSet(charactersIn: "\"'=:")
        .union(.whitespacesAndNewlines)
    )
  }

  private static func sanitizedURLString(_ string: String) -> String {
    string.trimmingCharacters(
      in: CharacterSet(charactersIn: ".,);]>")
    )
  }

  private static func sanitizedIdentifier(_ value: String) -> String {
    value.trimmingCharacters(
      in: CharacterSet(charactersIn: "\"',:;)]}>")
        .union(.whitespacesAndNewlines)
    )
  }

  private static let articleIDKeys = Set(["articleID", "articleId"])

  // Local News storage also contains topic and channel IDs. Article IDs have
  // consistently shown up as longer A*/P* tokens in the observed payloads.
  private static func isLikelyArticleID(_ id: String) -> Bool {
    guard let prefix = id.first else {
      return false
    }

    return (prefix == "A" || prefix == "P") && id.count >= 16
  }

  private var appleNewsURLPattern: Regex<Substring> {
    #/https?:\/\/apple\.news\/[A-Za-z0-9_-]+(?:\?[^\s"<>]+)?/#
  }

  private var inlineArticleIDPattern: Regex<(Substring, Substring)> {
    #/articleI[Dd][^A-Za-z0-9_-]+([A-Za-z0-9_-]{8,})/#
  }

  private static let standaloneArticleIDRegex = try! NSRegularExpression(
    pattern: #"(?<![A-Za-z0-9_-])[AP][A-Za-z0-9_-]{22}(?![A-Za-z0-9_-])"#
  )
}

struct HeadlineArchivePublisherURLExtractor: Sendable {
  let stringExtractor: BinaryStringExtractor

  init(stringExtractor: BinaryStringExtractor = BinaryStringExtractor()) {
    self.stringExtractor = stringExtractor
  }

  func publisherReference(in archiveData: Data) throws
    -> PublisherArticleReference
  {
    for candidate in candidateURLs(in: archiveData) {
      guard let reference = try? PublisherArticleReference(url: candidate),
        !Self.isAppleOwnedHost(reference.url.host)
      else {
        continue
      }

      return reference
    }

    throw LocalAppleNewsDiscoveryError.publisherURLNotFound
  }

  func candidateURLs(in archiveData: Data) -> [URL] {
    let urlPattern = #/https?:\/\/[^\s"<>]+/#
    var results = [URL]()
    var seen = Set<String>()

    for fragment in stringExtractor.strings(in: archiveData) {
      for match in fragment.matches(of: urlPattern) {
        let candidate = sanitizedURLString(String(match.output))

        guard seen.insert(candidate).inserted,
          let url = URL(string: candidate)
        else {
          continue
        }

        results.append(url)
      }
    }

    return results
  }

  private func sanitizedURLString(_ string: String) -> String {
    string.trimmingCharacters(
      in: CharacterSet(charactersIn: ".,);]>")
    )
  }

  private static func isAppleOwnedHost(_ host: String?) -> Bool {
    guard let host else {
      return true
    }

    let normalizedHost = host.lowercased()

    return normalizedHost == "apple.news"
      || normalizedHost.hasSuffix(".apple.news")
      || normalizedHost == "apple.com"
      || normalizedHost.hasSuffix(".apple.com")
  }
}

struct LocalReferralEntryMappingExtractor: Sendable {
  let publisherExtractor: HeadlineArchivePublisherURLExtractor

  init(
    publisherExtractor: HeadlineArchivePublisherURLExtractor =
      HeadlineArchivePublisherURLExtractor()
  ) {
    self.publisherExtractor = publisherExtractor
  }

  func mappings(inEntryData data: Data) throws -> [ArticleMapping] {
    try mappings(in: JSONDecoder().decode(LocalReferralEntry.self, from: data))
  }

  func mappings(in entry: LocalReferralEntry) -> [ArticleMapping] {
    var seenAppleNewsIDs = Set<String>()

    return entry.headlines.compactMap { headline in
      guard let mapping = mapping(for: headline),
        seenAppleNewsIDs.insert(mapping.id).inserted
      else {
        return nil
      }

      return mapping
    }
  }

  private func mapping(for headline: LocalReferralEntry.Headline)
    -> ArticleMapping?
  {
    guard let actionURL = headline.actionURL,
      let archiveData = headline.headlineArchive,
      let appleNews = try? AppleNewsArticleReference(url: actionURL),
      let publisher = try? publisherExtractor.publisherReference(
        in: archiveData
      )
    else {
      return nil
    }

    return ArticleMapping(appleNews: appleNews, publisher: publisher)
  }
}

struct LocalReferralEntryDiscovery: Sendable {
  let fileFinder: LocalDiscoveryFileFinder
  let extractor: LocalReferralEntryMappingExtractor

  init(
    fileFinder: LocalDiscoveryFileFinder = LocalDiscoveryFileFinder(),
    extractor: LocalReferralEntryMappingExtractor =
      LocalReferralEntryMappingExtractor()
  ) {
    self.fileFinder = fileFinder
    self.extractor = extractor
  }

  func mappings(in rootURL: URL) throws -> [ArticleMapping] {
    var results = [ArticleMapping]()

    for entryURL in try fileFinder.entryFiles(in: rootURL) {
      let data = try Data(contentsOf: entryURL, options: [.mappedIfSafe])
      results.append(contentsOf: try extractor.mappings(inEntryData: data))
    }

    return results
  }
}

struct LocalAppleNewsReferenceDiscoverer: Sendable {
  let fileFinder: LocalDiscoveryFileFinder
  let extractor: LocalAppleNewsReferenceExtractor

  init(
    fileFinder: LocalDiscoveryFileFinder = LocalDiscoveryFileFinder(),
    extractor: LocalAppleNewsReferenceExtractor =
      LocalAppleNewsReferenceExtractor()
  ) {
    self.fileFinder = fileFinder
    self.extractor = extractor
  }

  func articleReferences(in rootURLs: [URL]) -> [AppleNewsArticleReference] {
    var results = [AppleNewsArticleReference]()
    var seenIDs = Set<String>()

    for fileURL in fileFinder.regularFiles(in: rootURLs) {
      guard
        let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
      else {
        continue
      }

      for reference in extractor.articleReferences(in: data)
      where seenIDs.insert(reference.id).inserted {
        results.append(reference)
      }
    }

    return results
  }
}

private enum SQLiteColumnValue {
  case text(String)
  case blob(Data)
}

private func visitSQLiteColumnValues(
  at url: URL,
  query: String,
  _ visit: (SQLiteColumnValue) -> Void
) {
  guard FileManager.default.fileExists(atPath: url.path) else {
    return
  }

  var database: OpaquePointer?
  guard
    sqlite3_open_v2(
      url.path,
      &database,
      SQLITE_OPEN_READONLY,
      nil
    ) == SQLITE_OK,
    let database
  else {
    sqlite3_close(database)
    return
  }
  defer { sqlite3_close(database) }

  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
    let statement
  else {
    sqlite3_finalize(statement)
    return
  }
  defer { sqlite3_finalize(statement) }

  while sqlite3_step(statement) == SQLITE_ROW {
    switch sqlite3_column_type(statement, 0) {
    case SQLITE_BLOB:
      let count = Int(sqlite3_column_bytes(statement, 0))
      guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
        continue
      }
      visit(.blob(Data(bytes: bytes, count: count)))
    case SQLITE_TEXT:
      let count = Int(sqlite3_column_bytes(statement, 0))
      guard count > 0, let bytes = sqlite3_column_text(statement, 0) else {
        continue
      }
      let data = Data(bytes: bytes, count: count)
      visit(.text(String(decoding: data, as: UTF8.self)))
    default:
      continue
    }
  }
}

struct LocalAppleNewsDatabaseReferenceDiscoverer: Sendable {
  let databaseURLs: LocalAppleNewsDatabaseURLs
  let extractor: LocalAppleNewsReferenceExtractor
  let cache: LocalAppleNewsDatabaseReferenceCache?

  init(
    databaseURLs: LocalAppleNewsDatabaseURLs = .live,
    extractor: LocalAppleNewsReferenceExtractor =
      LocalAppleNewsReferenceExtractor(),
    cache: LocalAppleNewsDatabaseReferenceCache? = .live
  ) {
    self.databaseURLs = databaseURLs
    self.extractor = extractor
    self.cache = cache
  }

  func articleReferences(
    progress: ((String) -> Void)? = nil
  ) -> [AppleNewsArticleReference] {
    if let cachedReferences = cache?.articleReferences(for: databaseURLs) {
      progress?(
        "Using cached protected store results (\(cachedReferences.count) Apple News URLs)."
      )
      return cachedReferences
    }

    var results = [AppleNewsArticleReference]()
    var seenIDs = Set<String>()

    progress?("Scanning protected store article_exposures...")
    append(
      articleExposureReferences(),
      label: "article_exposures",
      to: &results,
      seenIDs: &seenIDs,
      progress: progress
    )
    progress?("Scanning protected store feeddatabase...")
    append(
      feedDatabaseReferences(),
      label: "feeddatabase",
      to: &results,
      seenIDs: &seenIDs,
      progress: progress
    )
    progress?("Scanning protected store today-feed-db...")
    append(
      todayFeedReferences(),
      label: "today-feed-db",
      to: &results,
      seenIDs: &seenIDs,
      progress: progress
    )

    cache?.save(results, for: databaseURLs)
    progress?("Cached \(results.count) protected-store Apple News URLs.")

    return results
  }

  private func articleExposureReferences() -> [AppleNewsArticleReference] {
    var results = [AppleNewsArticleReference]()

    visitSQLiteColumnValues(
      at: databaseURLs.articleExposuresURL,
      query: "SELECT id FROM ItemExposure"
    ) { value in
      guard case .text(let id) = value else {
        return
      }

      guard let reference = try? AppleNewsArticleReference(id: id) else {
        return
      }

      results.append(reference)
    }

    return results
  }

  private func feedDatabaseReferences() -> [AppleNewsArticleReference] {
    var results = [AppleNewsArticleReference]()
    var seenIDs = Set<String>()

    visitSQLiteColumnValues(
      at: databaseURLs.feedDatabaseURL,
      query: "SELECT encoded FROM feed_item"
    ) { value in
      let references: [AppleNewsArticleReference] =
        switch value {
        case .blob(let data):
          if let itemID = extractor.stringExtractor.string(in: data, at: 1),
            let reference = try? AppleNewsArticleReference(id: itemID)
          {
            [reference]
          } else {
            extractor.articleReferences(in: data)
          }
        case .text(let string):
          extractor.articleReferences(in: Data(string.utf8))
        }

      for reference in references where seenIDs.insert(reference.id).inserted {
        results.append(reference)
      }
    }

    return results
  }

  private func todayFeedReferences() -> [AppleNewsArticleReference] {
    extractedReferences(
      at: databaseURLs.todayFeedDatabaseURL,
      queries: [
        "SELECT data FROM blobs",
        "SELECT itemIds FROM groups",
        "SELECT itemIds FROM group_trackers",
      ]
    )
  }

  private func extractedReferences(at url: URL, queries: [String])
    -> [AppleNewsArticleReference]
  {
    var results = [AppleNewsArticleReference]()
    var seenIDs = Set<String>()

    for query in queries {
      visitSQLiteColumnValues(at: url, query: query) { value in
        let references =
          switch value {
          case .blob(let data):
            extractor.articleReferences(in: data)
          case .text(let string):
            extractor.articleReferences(in: Data(string.utf8))
          }

        for reference in references where seenIDs.insert(reference.id).inserted
        {
          results.append(reference)
        }
      }
    }

    return results
  }

  private func append(
    _ references: [AppleNewsArticleReference],
    label: String,
    to results: inout [AppleNewsArticleReference],
    seenIDs: inout Set<String>,
    progress: ((String) -> Void)?
  ) {
    let initialCount = results.count

    for reference in references where seenIDs.insert(reference.id).inserted {
      results.append(reference)
    }

    progress?(
      "Protected store \(label) added \(results.count - initialCount) unique Apple News URLs (\(results.count) total)."
    )
  }
}

struct LocalAppleNewsDiscoveryResult: Sendable {
  let mappings: [ArticleMapping]
  let articleReferences: [AppleNewsArticleReference]
}

struct LocalAppleNewsDiscovery: Sendable {
  let entryDiscovery: LocalReferralEntryDiscovery
  let databaseDiscoverer: LocalAppleNewsDatabaseReferenceDiscoverer
  let referenceDiscoverer: LocalAppleNewsReferenceDiscoverer

  init(
    entryDiscovery: LocalReferralEntryDiscovery = LocalReferralEntryDiscovery(),
    databaseDiscoverer: LocalAppleNewsDatabaseReferenceDiscoverer =
      LocalAppleNewsDatabaseReferenceDiscoverer(),
    referenceDiscoverer: LocalAppleNewsReferenceDiscoverer =
      LocalAppleNewsReferenceDiscoverer()
  ) {
    self.entryDiscovery = entryDiscovery
    self.databaseDiscoverer = databaseDiscoverer
    self.referenceDiscoverer = referenceDiscoverer
  }

  func discover(
    referralItemsURL: URL,
    searchRootURLs: [URL],
    includeFileScan: Bool = false,
    progress: ((String) -> Void)? = nil
  ) throws -> LocalAppleNewsDiscoveryResult {
    progress?("Scanning referral items for local publisher mappings...")
    var mappingsByID = [String: ArticleMapping]()

    for mapping in try entryDiscovery.mappings(in: referralItemsURL) {
      mappingsByID[mapping.id] = mapping
    }

    progress?(
      "Referral items yielded \(mappingsByID.count) local publisher mappings."
    )

    var articleReferencesByID = [String: AppleNewsArticleReference]()

    progress?("Scanning protected Apple News databases...")
    for reference in databaseDiscoverer.articleReferences(progress: progress)
    where mappingsByID[reference.id] == nil {
      articleReferencesByID[reference.id] = reference
    }

    progress?(
      "Protected databases yielded \(articleReferencesByID.count) Apple News URLs without local mappings."
    )

    if includeFileScan {
      progress?(
        "Scanning \(searchRootURLs.count) local root(s) for additional Apple News URLs..."
      )
      let countBeforeFileScan = articleReferencesByID.count

      for reference in referenceDiscoverer.articleReferences(in: searchRootURLs)
      where mappingsByID[reference.id] == nil {
        articleReferencesByID[reference.id] = reference
      }

      progress?(
        "Raw file scan added \(articleReferencesByID.count - countBeforeFileScan) Apple News URLs."
      )
    }

    let articleReferences = articleReferencesByID.values.sorted {
      $0.url.absoluteString < $1.url.absoluteString
    }
    let mappings = mappingsByID.values.sorted {
      $0.appleNews.url.absoluteString < $1.appleNews.url.absoluteString
    }

    return LocalAppleNewsDiscoveryResult(
      mappings: mappings,
      articleReferences: articleReferences
    )
  }
}
