import ArgumentParser
import Foundation

struct StoreOptions: ParsableArguments {
  @Option(
    name: .customLong("store-path"),
    help: "Custom location for the SwiftData store file."
  )
  var storePath: String?

  var store: ArticleMappings {
    get throws {
      guard let storePath else {
        return try ArticleMappings()
      }

      let expandedPath = NSString(string: storePath).expandingTildeInPath
      return try ArticleMappings(
        location: .file(URL(filePath: expandedPath))
      )
    }
  }
}

private func writeError(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

struct AddMapping: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add",
    abstract: "Insert or update an Apple News to publisher URL mapping."
  )

  @OptionGroup var storeOptions: StoreOptions
  @Argument(
    help:
      "Apple News URL, for example https://apple.news/AgYBtZhCLTD2ZCmgVQI1g6w"
  )
  var appleNews: AppleNewsArticleReference
  @Argument(help: "Publisher article URL.")
  var publisher: PublisherArticleReference

  mutating func run() throws {
    let mapping = ArticleMapping(appleNews: appleNews, publisher: publisher)
    try storeOptions.store.upsert(mapping)

    print(mapping)
  }
}

struct ResolveAppleNews: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "resolve-apple",
    abstract:
      "Fetch Apple News pages, extract publisher URLs, and persist mappings."
  )

  @OptionGroup var storeOptions: StoreOptions

  @Argument(help: "One or more Apple News URLs.")
  var appleNews: [AppleNewsArticleReference]

  mutating func run() async throws {
    let store = try storeOptions.store
    let resolver = AppleNewsMappingResolver()
    var failures = 0

    for article in appleNews {
      do {
        let mapping = try await resolver.resolve(article)
        try store.upsert(mapping)
        print(mapping)
      } catch {
        failures += 1
        writeError(
          "Failed to resolve \(article.url.absoluteString): \(error.localizedDescription)"
        )
      }
    }

    if failures > 0 {
      throw ExitCode.failure
    }
  }
}

struct LookupAppleNews: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lookup-apple",
    abstract: "Resolve an Apple News URL to its publisher URL."
  )

  @OptionGroup var storeOptions: StoreOptions
  @Argument(help: "Apple News URL.")
  var appleNews: AppleNewsArticleReference

  mutating func run() throws {
    guard let mapping = try storeOptions.store.mapping(forAppleNews: appleNews)
    else {
      throw ArticleMappingStoreError.missingMapping(
        "No publisher mapping found for \(appleNews.url.absoluteString)"
      )
    }

    print(mapping.publisher.url.absoluteString)
  }
}

struct LookupPublisher: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "lookup-publisher",
    abstract: "Resolve a publisher URL to its Apple News URL."
  )

  @OptionGroup var storeOptions: StoreOptions
  @Argument(help: "Publisher article URL.")
  var publisher: PublisherArticleReference

  mutating func run() throws {
    guard let mapping = try storeOptions.store.mapping(forPublisher: publisher)
    else {
      throw ArticleMappingStoreError.missingMapping(
        "No Apple News mapping found for \(publisher.url.absoluteString)"
      )
    }

    print(mapping.appleNews.url.absoluteString)
  }
}

struct ListMappings: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List recent stored mappings."
  )

  @OptionGroup var storeOptions: StoreOptions

  @Option(help: "Maximum number of mappings to display.")
  var limit = 20

  mutating func run() throws {
    let mappings = try storeOptions.store.recentMappings(limit: limit)

    guard !mappings.isEmpty else {
      print("No mappings stored yet.")
      return
    }

    for mapping in mappings {
      print(mapping)
    }
  }
}
