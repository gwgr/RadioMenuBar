import Foundation

struct Station: Codable, Identifiable, Hashable {
    let name: String
    let url: URL

    var id: String { url.absoluteString }
}
