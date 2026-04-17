import Foundation

public struct ArticleMapping: Identifiable, Hashable, Codable, Sendable,
  CustomStringConvertible
{
  public let appleNews: AppleNewsArticleReference
  public let publisher: PublisherArticleReference
  public let discoveredAt: Date
  public let lastResolvedAt: Date

  public init(
    appleNews: AppleNewsArticleReference,
    publisher: PublisherArticleReference,
    discoveredAt: Date = .now,
    lastResolvedAt: Date = .now
  ) {
    self.appleNews = appleNews
    self.publisher = publisher
    self.discoveredAt = discoveredAt
    self.lastResolvedAt = lastResolvedAt
  }

  public var id: String {
    appleNews.id
  }

  public var description: String {
    "\(appleNews) -> \(publisher)"
  }
}
