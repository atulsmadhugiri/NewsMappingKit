import ArgumentParser
import Foundation
import NewsMappingCore

extension AppleNewsArticleReference: ExpressibleByArgument {
  public init?(argument: String) {
    guard let url = URL(string: argument),
      let reference = try? Self(url: url)
    else {
      return nil
    }

    self = reference
  }
}

extension PublisherArticleReference: ExpressibleByArgument {
  public init?(argument: String) {
    guard let url = URL(string: argument),
      let reference = try? Self(url: url)
    else {
      return nil
    }

    self = reference
  }
}
