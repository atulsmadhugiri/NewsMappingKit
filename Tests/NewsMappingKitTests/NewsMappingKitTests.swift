import Foundation
import Testing

@testable import NewsMappingKit

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
