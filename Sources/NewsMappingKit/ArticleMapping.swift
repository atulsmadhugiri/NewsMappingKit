import Foundation

struct ArticleMapping: Identifiable, Hashable, Codable, Sendable,
  CustomStringConvertible
{
  let appleNews: AppleNewsArticleReference
  let publisher: PublisherArticleReference
  let discoveredAt: Date
  let lastResolvedAt: Date

  init(
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

  var id: String {
    appleNews.id
  }

  var description: String {
    "\(appleNews) -> \(publisher)"
  }
}
