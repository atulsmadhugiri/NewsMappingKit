import Foundation

private struct AppleNewsDiscoveryRecord: Codable, Sendable {
  let appleNewsID: String
  let appleNewsURLString: String
  var firstDiscoveredAt: Date
  var lastDiscoveredAt: Date

  init(
    article: AppleNewsArticleReference,
    firstDiscoveredAt: Date,
    lastDiscoveredAt: Date
  ) {
    appleNewsID = article.id
    appleNewsURLString = article.url.absoluteString
    self.firstDiscoveredAt = firstDiscoveredAt
    self.lastDiscoveredAt = lastDiscoveredAt
  }

  var article: AppleNewsArticleReference {
    get throws {
      guard let url = URL(string: appleNewsURLString) else {
        throw ArticleMappingStoreError.invalidStoredURL(appleNewsURLString)
      }

      return try AppleNewsArticleReference(url: url)
    }
  }
}

final class AppleNewsDiscoveries {
  enum Location: Sendable {
    case file(URL)
    case inMemory
  }

  private let location: Location
  private var recordsByID: [String: AppleNewsDiscoveryRecord]

  init(location: Location) throws {
    self.location = location

    switch location {
    case .file(let fileURL):
      recordsByID = try Self.loadRecords(from: fileURL)
    case .inMemory:
      recordsByID = [:]
    }
  }

  func upsertAll(_ articles: [AppleNewsArticleReference]) throws {
    guard !articles.isEmpty else {
      return
    }

    let timestamp = Date()

    for article in articles {
      if var existingRecord = recordsByID[article.id] {
        existingRecord.lastDiscoveredAt = timestamp
        recordsByID[article.id] = existingRecord
      } else {
        recordsByID[article.id] = AppleNewsDiscoveryRecord(
          article: article,
          firstDiscoveredAt: timestamp,
          lastDiscoveredAt: timestamp
        )
      }
    }

    try persist()
  }

  func recentArticles(limit: Int) throws -> [AppleNewsArticleReference] {
    try recentRecords(limit: limit).map { try $0.article }
  }

  private func recentRecords(limit: Int) -> [AppleNewsDiscoveryRecord] {
    Array(
      sortedRecords()
        .prefix(max(limit, 0))
    )
  }

  private func sortedRecords() -> [AppleNewsDiscoveryRecord] {
    recordsByID.values.sorted {
      if $0.lastDiscoveredAt != $1.lastDiscoveredAt {
        return $0.lastDiscoveredAt > $1.lastDiscoveredAt
      }

      return $0.appleNewsID < $1.appleNewsID
    }
  }

  private func persist() throws {
    guard case .file(let fileURL) = location else {
      return
    }

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(sortedRecords())
    try data.write(to: fileURL, options: [.atomic])
  }

  private static func loadRecords(from fileURL: URL) throws
    -> [String: AppleNewsDiscoveryRecord]
  {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return [:]
    }

    let data = try Data(contentsOf: fileURL)
    let records = try JSONDecoder().decode(
      [AppleNewsDiscoveryRecord].self,
      from: data
    )

    return Dictionary(
      uniqueKeysWithValues: records.map { ($0.appleNewsID, $0) }
    )
  }
}
