import ArgumentParser
import Foundation

typealias ProgressHandler = @Sendable (String) -> Void

private enum ResolutionConfiguration {
  // Apple News resolution is network-bound, but live probes show throughput
  // drops again once we push much beyond a few dozen concurrent fetches.
  static let defaultConcurrency = 32

  static func progressInterval(for total: Int) -> Int {
    max(1, min(250, max(total / 100, 1)))
  }

  static func progressPrefix(processed: Int, total: Int) -> String {
    "[\(processed.formatted())/\(total.formatted())]"
  }
}

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

      return try ArticleMappings(
        location: .file(storePath.expandedFileURL)
      )
    }
  }
}

struct ResolutionOptions: ParsableArguments {
  @Option(
    name: .customLong("resolution-concurrency"),
    help:
      "Maximum number of concurrent Apple News page fetches while resolving missing publisher mappings."
  )
  var concurrency = ResolutionConfiguration.defaultConcurrency

  func validate() throws {
    guard concurrency > 0 else {
      throw ValidationError(
        "--resolution-concurrency must be greater than 0."
      )
    }
  }
}

struct LocalDiscoveryOptions: ParsableArguments {
  @Option(
    name: .customLong("referral-items-path"),
    help: "Custom location for the Apple News referralItems directory."
  )
  var referralItemsPath: String?

  @Option(
    name: .customLong("scan-root-path"),
    help:
      "Additional local directories to include in the exhaustive file scan. Can be repeated."
  )
  var scanRootPaths: [String] = []

  @Flag(
    name: .customLong("exhaustive-file-scan"),
    inversion: .prefixedNo,
    help:
      "Also scan raw local files for extra Apple News URLs beyond referral entries and protected databases."
  )
  var exhaustiveFileScan = true

  var referralItemsURL: URL {
    guard let referralItemsPath else {
      return LocalAppleNewsPaths.referralItemsURL
    }

    return referralItemsPath.expandedFileURL
  }

  var searchRootURLs: [URL] {
    deduplicatedURLs(
      [referralItemsURL.deletingLastPathComponent()]
        + LocalAppleNewsPaths.defaultSearchRootURLs
        + scanRootPaths.map(\.expandedFileURL)
    )
  }
  @Flag(
    name: .customLong("resolve-missing"),
    inversion: .prefixedNo,
    help:
      "Fetch Apple News pages for discovered Apple News URLs that do not already have a local publisher mapping."
  )
  var resolveMissing = true
}

extension String {
  fileprivate var expandedFileURL: URL {
    URL(filePath: NSString(string: self).expandingTildeInPath)
  }
}

private func writeError(_ message: String) {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
}

private func writeProgress(_ message: String) {
  writeError("[progress] \(message)")
}

private func deduplicatedURLs(_ urls: [URL]) -> [URL] {
  var seenPaths = Set<String>()

  return urls.filter { url in
    seenPaths.insert(url.path).inserted
  }
}

private func discoveredAppleNewsReferences(
  from result: LocalAppleNewsDiscoveryResult
) -> [AppleNewsArticleReference] {
  Array(
    Dictionary(
      (result.mappings.map(\.appleNews) + result.articleReferences).map {
        ($0.id, $0)
      },
      uniquingKeysWith: { _, latest in latest }
    ).values
  )
  .sorted(using: KeyPathComparator(\.id))
}

private func persistAndPrint(
  _ mapping: ArticleMapping,
  using store: ArticleMappings
) throws {
  try store.upsert(mapping)
  print(mapping)
}

private func persistAndPrint(
  _ mappings: [ArticleMapping],
  using store: ArticleMappings
) throws -> Int {
  guard !mappings.isEmpty else {
    return 0
  }

  try store.upsertAll(mappings)

  for mapping in mappings {
    print(mapping)
  }

  return mappings.count
}

private struct ResolutionSummary {
  var persistedCount = 0
  var reusedCount = 0
  var failures = 0
}

private enum ResolutionOutcome: Sendable {
  case mapping(index: Int, ArticleMapping)
  case failure(index: Int, AppleNewsArticleReference, String)
}

private func resolveOutcome(
  for article: AppleNewsArticleReference,
  at index: Int,
  using resolver: AppleNewsMappingResolver
) async -> ResolutionOutcome {
  do {
    return .mapping(index: index, try await resolver.resolve(article))
  } catch {
    return .failure(index: index, article, resolutionErrorDescription(error))
  }
}

private func resolveAndPersist(
  _ articles: [AppleNewsArticleReference],
  using store: ArticleMappings,
  resolver: AppleNewsMappingResolver = AppleNewsMappingResolver(),
  reuseStoredMappings: Bool = false,
  maxConcurrency: Int = ResolutionConfiguration.defaultConcurrency,
  progress: ProgressHandler? = nil
) async throws -> ResolutionSummary {
  var summary = ResolutionSummary()
  var orderedMappings = [(Int, ArticleMapping)]()
  var unresolvedArticles = [(Int, AppleNewsArticleReference)]()
  orderedMappings.reserveCapacity(articles.count)
  unresolvedArticles.reserveCapacity(articles.count)

  let storedMappingsByID: [String: ArticleMapping] =
    if reuseStoredMappings {
      try store.mappingsByAppleNewsID()
    } else {
      [:]
    }

  for (index, article) in articles.enumerated() {
    if let storedMapping = storedMappingsByID[article.id] {
      orderedMappings.append((index, storedMapping))
      summary.reusedCount += 1
    } else {
      unresolvedArticles.append((index, article))
    }
  }

  if summary.reusedCount > 0 {
    progress?(
      "Reused \(summary.reusedCount) stored mappings without refetching."
    )
  }

  if !unresolvedArticles.isEmpty {
    progress?(
      "Resolving publisher URLs \(ResolutionConfiguration.progressPrefix(processed: 0, total: unresolvedArticles.count)) with up to \(maxConcurrency.formatted()) concurrent requests..."
    )
  }

  let progressInterval = ResolutionConfiguration.progressInterval(
    for: unresolvedArticles.count
  )
  var processedCount = 0
  var iterator = unresolvedArticles.makeIterator()

  await withTaskGroup(of: ResolutionOutcome.self) { group in
    for _ in 0..<min(maxConcurrency, unresolvedArticles.count) {
      guard let (index, article) = iterator.next() else {
        break
      }

      group.addTask {
        await resolveOutcome(for: article, at: index, using: resolver)
      }
    }

    while let outcome = await group.next() {
      processedCount += 1

      switch outcome {
      case .mapping(let index, let mapping):
        orderedMappings.append((index, mapping))
        summary.persistedCount += 1
      case .failure(_, let article, let message):
        summary.failures += 1
        writeError(
          "\(ResolutionConfiguration.progressPrefix(processed: processedCount, total: unresolvedArticles.count)) Failed to resolve \(article.url.absoluteString): \(message)"
        )
      }

      if processedCount == unresolvedArticles.count
        || processedCount.isMultiple(of: progressInterval)
      {
        progress?(
          "Resolving publisher URLs \(ResolutionConfiguration.progressPrefix(processed: processedCount, total: unresolvedArticles.count)) (\(summary.persistedCount.formatted()) succeeded, \(summary.failures.formatted()) failures)."
        )
      }

      if let (index, article) = iterator.next() {
        group.addTask {
          await resolveOutcome(for: article, at: index, using: resolver)
        }
      }
    }
  }

  let newMappings =
    orderedMappings
    .filter { storedMappingsByID[$0.1.id] == nil }
    .map(\.1)
  if !newMappings.isEmpty {
    try store.upsertAll(newMappings)
  }

  for (_, mapping) in orderedMappings.sorted(by: { $0.0 < $1.0 }) {
    print(mapping)
  }

  return summary
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
    try persistAndPrint(mapping, using: storeOptions.store)
  }
}

struct ResolveAppleNews: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "resolve-apple",
    abstract:
      "Fetch Apple News pages, extract publisher URLs, and persist mappings."
  )

  @OptionGroup var storeOptions: StoreOptions
  @OptionGroup var resolutionOptions: ResolutionOptions

  @Argument(help: "One or more Apple News URLs.")
  var appleNews: [AppleNewsArticleReference]

  mutating func run() async throws {
    let store = try storeOptions.store
    let summary = try await resolveAndPersist(
      appleNews,
      using: store,
      maxConcurrency: resolutionOptions.concurrency,
      progress: writeProgress
    )

    if summary.failures > 0 {
      throw ExitCode.failure
    }
  }
}

struct DiscoverLocalMappings: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "discover-local",
    abstract:
      "Scan local Apple News storage, harvest Apple News URLs, resolve publisher URLs, and persist mappings."
  )

  @OptionGroup var storeOptions: StoreOptions
  @OptionGroup var localDiscoveryOptions: LocalDiscoveryOptions
  @OptionGroup var resolutionOptions: ResolutionOptions

  mutating func run() async throws {
    let store = try storeOptions.store
    let initialCount = try store.mappingCount()
    let discovery = LocalAppleNewsDiscovery()
    writeProgress("Starting local discovery...")
    let result = try discovery.discover(
      referralItemsURL: localDiscoveryOptions.referralItemsURL,
      searchRootURLs: localDiscoveryOptions.searchRootURLs,
      includeFileScan: localDiscoveryOptions.exhaustiveFileScan,
      progress: writeProgress
    )
    let discoveredAppleNews = discoveredAppleNewsReferences(from: result)
    if !discoveredAppleNews.isEmpty {
      writeProgress(
        "Persisting \(discoveredAppleNews.count) discovered Apple News URLs..."
      )
      try store.upsertDiscoveries(discoveredAppleNews)
      writeProgress(
        "Persisted \(discoveredAppleNews.count) discovered Apple News URLs."
      )
    }
    if !result.mappings.isEmpty {
      writeProgress(
        "Persisting \(result.mappings.count) local publisher mappings..."
      )
    }
    let localCount = try persistAndPrint(result.mappings, using: store)
    let resolutionSummary =
      if localDiscoveryOptions.resolveMissing {
        try await resolveAndPersist(
          result.articleReferences,
          using: store,
          reuseStoredMappings: true,
          maxConcurrency: resolutionOptions.concurrency,
          progress: writeProgress
        )
      } else {
        ResolutionSummary()
      }

    if localCount > 0 {
      writeProgress("Persisted \(localCount) local publisher mappings.")
    }

    if resolutionSummary.reusedCount > 0 {
      writeProgress(
        "Reused \(resolutionSummary.reusedCount) existing stored mappings."
      )
    }

    if !localDiscoveryOptions.resolveMissing, !result.articleReferences.isEmpty
    {
      writeProgress(
        "Skipping network resolution for \(result.articleReferences.count) Apple News URLs."
      )
    }

    writeProgress("Local discovery complete.")

    print("Discovered \(discoveredAppleNews.count) Apple News URLs.")

    if !result.articleReferences.isEmpty {
      print(
        "Found \(result.articleReferences.count) Apple News URLs without local publisher mappings."
      )
    }

    if localCount + resolutionSummary.persistedCount
      + resolutionSummary.reusedCount
      == 0
    {
      print("No mappings discovered.")
    }

    if resolutionSummary.failures > 0 {
      writeError(
        "Skipped \(resolutionSummary.failures) Apple News URLs that could not be resolved."
      )
    }

    let finalCount = try store.mappingCount()
    print("Net new mappings added: \(max(finalCount - initialCount, 0))")
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
    abstract: "List recent resolved Apple News mappings."
  )

  @OptionGroup var storeOptions: StoreOptions

  @Option(help: "Maximum number of mappings to display.")
  var limit = 20

  mutating func run() throws {
    let store = try storeOptions.store
    let mappingsByDiscovery = try store.recentDiscoveredMappings(limit: limit)

    if !mappingsByDiscovery.isEmpty {
      for mapping in mappingsByDiscovery {
        print(mapping)
      }
      return
    }

    let mappings = try store.recentMappings(limit: limit)

    guard !mappings.isEmpty else {
      print("No mappings stored yet.")
      return
    }

    for mapping in mappings {
      print(mapping)
    }
  }
}
