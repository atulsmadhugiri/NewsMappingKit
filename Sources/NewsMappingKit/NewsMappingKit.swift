import ArgumentParser

@main
struct NewsMappingKit: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "news-mapping-kit",
    abstract: "Store and resolve Apple News article mappings.",
    subcommands: [
      AddMapping.self,
      LookupAppleNews.self,
      LookupPublisher.self,
      ListMappings.self,
    ]
  )
}
