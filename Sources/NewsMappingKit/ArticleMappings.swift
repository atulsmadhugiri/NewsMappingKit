import Foundation
import SwiftData

enum ArticleMappingStoreError: LocalizedError {
  case invalidStoredURL(String)
  case missingMapping(String)

  var errorDescription: String? {
    switch self {
    case .invalidStoredURL(let value):
      return "Stored mapping contains an invalid URL: \(value)"
    case .missingMapping(let message):
      return message
    }
  }
}

enum StoredAppleNewsListItem: Sendable, CustomStringConvertible {
  case mapping(ArticleMapping)
  case article(AppleNewsArticleReference)

  var description: String {
    switch self {
    case .mapping(let mapping):
      return mapping.description
    case .article(let article):
      return article.url.absoluteString
    }
  }
}

final class ArticleMappings {
  enum Location: Sendable {
    case automatic
    case file(URL)
    case inMemory
  }

  private static let storeName = "NewsMappingKit"

  private let context: ModelContext
  private let discoveries: AppleNewsDiscoveries

  init(location: Location = .automatic) throws {
    let container = try ModelContainer(
      for: ArticleMappingRecord.self,
      configurations: Self.configuration(for: location)
    )

    context = ModelContext(container)
    context.autosaveEnabled = false
    discoveries = try AppleNewsDiscoveries(
      location: try Self.discoveryLocation(for: location)
    )
  }

  func upsert(_ mapping: ArticleMapping) throws {
    try upsert(mapping, saveChanges: true)
    try discoveries.upsertAll([mapping.appleNews])
  }

  func upsertAll(_ mappings: [ArticleMapping]) throws {
    for mapping in mappings {
      try upsert(mapping, saveChanges: false)
    }

    try persistChanges()
    try discoveries.upsertAll(mappings.map(\.appleNews))
  }

  func allMappings() throws -> [ArticleMapping] {
    try context.fetch(FetchDescriptor<ArticleMappingRecord>()).map {
      try $0.mapping
    }
  }

  func mappingsByAppleNewsID() throws -> [String: ArticleMapping] {
    Dictionary(uniqueKeysWithValues: try allMappings().map { ($0.id, $0) })
  }

  func upsertDiscoveries(_ articles: [AppleNewsArticleReference]) throws {
    try discoveries.upsertAll(articles)
  }

  func recentDiscoveries(limit: Int = 20) throws -> [AppleNewsArticleReference]
  {
    try discoveries.recentArticles(limit: limit)
  }

  func recentDiscoveryItems(limit: Int = 20) throws -> [StoredAppleNewsListItem]
  {
    let discoveries = try recentDiscoveries(limit: limit)
    guard !discoveries.isEmpty else {
      return []
    }

    let mappingsByID = try mappingsByAppleNewsID()

    return discoveries.map { article in
      if let mapping = mappingsByID[article.id] {
        return .mapping(mapping)
      }

      return .article(article)
    }
  }

  private func upsert(_ mapping: ArticleMapping, saveChanges: Bool) throws {
    let appleNewsMatch = try firstRecord(
      matching: #Predicate<ArticleMappingRecord> {
        $0.appleNewsID == mapping.appleNews.id
      }
    )
    let publisherMatch = try firstRecord(
      matching: #Predicate<ArticleMappingRecord> {
        $0.publisherURLString == mapping.publisher.url.absoluteString
      }
    )
    let record =
      appleNewsMatch ?? publisherMatch ?? ArticleMappingRecord(mapping: mapping)

    if appleNewsMatch == nil, publisherMatch == nil {
      context.insert(record)
    }

    record.update(from: mapping)

    if let duplicate = [appleNewsMatch, publisherMatch]
      .compactMap(\.self)
      .first(where: { $0 !== record })
    {
      context.delete(duplicate)
    }

    if saveChanges {
      try persistChanges()
    }
  }

  func mapping(forAppleNews article: AppleNewsArticleReference) throws
    -> ArticleMapping?
  {
    try firstRecord(
      matching: #Predicate<ArticleMappingRecord> {
        $0.appleNewsID == article.id
      }
    )?.mapping
  }

  func mapping(forPublisher article: PublisherArticleReference) throws
    -> ArticleMapping?
  {
    try firstRecord(
      matching: #Predicate<ArticleMappingRecord> {
        $0.publisherURLString == article.url.absoluteString
      }
    )?.mapping
  }

  func recentMappings(limit: Int = 20) throws -> [ArticleMapping] {
    var descriptor = FetchDescriptor<ArticleMappingRecord>(
      sortBy: [SortDescriptor(\.lastResolvedAt, order: .reverse)]
    )
    descriptor.fetchLimit = max(limit, 0)

    return try context.fetch(descriptor).map { try $0.mapping }
  }

  func mappingCount() throws -> Int {
    try context.fetch(FetchDescriptor<ArticleMappingRecord>()).count
  }

  private func firstRecord(
    matching predicate: Predicate<ArticleMappingRecord>
  ) throws -> ArticleMappingRecord? {
    try context.fetch(FetchDescriptor(predicate: predicate)).first
  }

  private func persistChanges() throws {
    guard context.hasChanges else {
      return
    }

    try context.save()
  }

  private static func configuration(for location: Location) throws
    -> ModelConfiguration
  {
    switch location {
    case .automatic:
      return try persistentConfiguration(at: defaultStoreURL())
    case .file(let storeURL):
      return try persistentConfiguration(at: storeURL)
    case .inMemory:
      return ModelConfiguration(
        storeName,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
      )
    }
  }

  private static func defaultStoreURL() -> URL {
    URL.applicationSupportDirectory.appending(
      path: storeName,
      directoryHint: .isDirectory
    ).appending(
      path: "ArticleMappings.store",
      directoryHint: .notDirectory
    )
  }

  private static func persistentConfiguration(at storeURL: URL) throws
    -> ModelConfiguration
  {
    try ensureParentDirectoryExists(for: storeURL)
    return ModelConfiguration(storeName, url: storeURL, cloudKitDatabase: .none)
  }

  private static func ensureParentDirectoryExists(for fileURL: URL) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
  }

  private static func discoveryLocation(for location: Location) throws
    -> AppleNewsDiscoveries.Location
  {
    switch location {
    case .automatic:
      return .file(discoveryFileURL(for: defaultStoreURL()))
    case .file(let storeURL):
      try ensureParentDirectoryExists(for: storeURL)
      return .file(discoveryFileURL(for: storeURL))
    case .inMemory:
      return .inMemory
    }
  }

  private static func discoveryFileURL(for storeURL: URL) -> URL {
    storeURL
      .deletingPathExtension()
      .appendingPathExtension("discoveries")
      .appendingPathExtension("json")
  }
}
