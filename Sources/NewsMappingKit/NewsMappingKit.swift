import ArgumentParser

@main
struct NewsMappingKit: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "news-mapping-kit",
    abstract: "A lightweight CLI scaffold for NewsMappingKit."
  )

  @Flag(help: "Emit extra startup details.")
  var verbose = false

  mutating func run() throws {
    if verbose {
      print("Starting NewsMappingKit CLI...")
    }

    print("NewsMappingKit CLI scaffold is ready.")
  }
}
