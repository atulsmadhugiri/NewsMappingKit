import Foundation
import SwiftData

@Model
final class ArticleMappingRecord {
  @Attribute(.unique) var appleNewsID: String
  @Attribute(.unique) var publisherURLString: String
  var appleNewsURLString: String
  var discoveredAt: Date
  var lastResolvedAt: Date

  init(mapping: ArticleMapping) {
    appleNewsID = mapping.appleNews.id
    appleNewsURLString = mapping.appleNews.url.absoluteString
    publisherURLString = mapping.publisher.url.absoluteString
    discoveredAt = mapping.discoveredAt
    lastResolvedAt = mapping.lastResolvedAt
  }

  func update(from mapping: ArticleMapping) {
    appleNewsID = mapping.appleNews.id
    appleNewsURLString = mapping.appleNews.url.absoluteString
    publisherURLString = mapping.publisher.url.absoluteString
    discoveredAt = min(discoveredAt, mapping.discoveredAt)
    lastResolvedAt = mapping.lastResolvedAt
  }

  var mapping: ArticleMapping {
    get throws {
      guard let appleNewsURL = URL(string: appleNewsURLString) else {
        throw ArticleMappingStoreError.invalidStoredURL(appleNewsURLString)
      }

      guard let publisherURL = URL(string: publisherURLString) else {
        throw ArticleMappingStoreError.invalidStoredURL(publisherURLString)
      }

      return try ArticleMapping(
        appleNews: AppleNewsArticleReference(url: appleNewsURL),
        publisher: PublisherArticleReference(url: publisherURL),
        discoveredAt: discoveredAt,
        lastResolvedAt: lastResolvedAt
      )
    }
  }
}
