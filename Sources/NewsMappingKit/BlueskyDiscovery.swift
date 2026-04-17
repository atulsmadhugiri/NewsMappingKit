import ArgumentParser
import Foundation
import NewsMappingCore

private func writeBlueskyProgress(_ message: String) {
  FileHandle.standardError.write(Data("[progress] \(message)\n".utf8))
}

struct DiscoverBlueskyAppleNews: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "discover-bluesky",
    abstract: "Search Bluesky posts for Apple News URLs."
  )

  @Option(
    name: .customLong("query"),
    help: "Bluesky search query."
  )
  var query = BlueskySearchDefaults.query

  @Option(
    name: .customLong("limit"),
    help: "Maximum number of unique Apple News URLs to print."
  )
  var limit = BlueskySearchDefaults.limit

  @Option(
    name: .customLong("max-pages"),
    help: "Maximum number of Bluesky search result pages to scan."
  )
  var maxPages = BlueskySearchDefaults.maxPages

  @Option(
    name: .customLong("bsky-identifier"),
    help: "Bluesky handle or DID for authenticated search paging."
  )
  var blueskyIdentifier: String?

  @Option(
    name: .customLong("bsky-app-password"),
    help:
      "Bluesky app password for authenticated search paging. Prefer the BLUESKY_APP_PASSWORD environment variable over passing this directly."
  )
  var blueskyAppPassword: String?

  mutating func run() async throws {
    let environment = ProcessInfo.processInfo.environment
    let credentials = try validatedCredentials(using: environment)

    writeBlueskyProgress("Searching Bluesky for Apple News URLs...")
    let references = try await BlueskySearchDiscoverer().articleReferences(
      query: query,
      limit: limit,
      maxPages: maxPages,
      credentials: credentials,
      progress: writeBlueskyProgress
    )

    for reference in references {
      print(reference.url.absoluteString)
    }

    writeBlueskyProgress(
      "Discovered \(references.count.formatted()) unique Apple News URLs from Bluesky."
    )
  }

  mutating func validate() throws {
    guard limit > 0 else {
      throw ValidationError("--limit must be greater than 0.")
    }

    guard maxPages > 0 else {
      throw ValidationError("--max-pages must be greater than 0.")
    }
  }

  private func validatedCredentials(
    using environment: [String: String]
  ) throws -> BlueskyCredentials? {
    let identifier = blueskyIdentifier ?? environment["BLUESKY_IDENTIFIER"]
    let appPassword = blueskyAppPassword ?? environment["BLUESKY_APP_PASSWORD"]

    if let identifier, let appPassword {
      return BlueskyCredentials(
        identifier: identifier,
        appPassword: appPassword
      )
    }

    if identifier != nil || appPassword != nil {
      throw ValidationError(
        "Provide both Bluesky credentials or neither of them."
      )
    }

    return nil
  }
}
