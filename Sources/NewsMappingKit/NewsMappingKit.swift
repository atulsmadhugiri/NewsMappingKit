import ArgumentParser

@main
struct NewsMappingKit: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "news-mapping-kit",
    abstract: "Store and resolve Apple News article mappings.",
    subcommands: [
      AddMapping.self,
      ResolveAppleNews.self,
      DiscoverLocalMappings.self,
      LookupAppleNews.self,
      LookupPublisher.self,
      ListMappings.self,
    ]
  )
}
