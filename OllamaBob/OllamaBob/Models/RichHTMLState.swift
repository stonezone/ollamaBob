import Foundation
import Combine
import CryptoKit

@MainActor
final class RichHTMLState: ObservableObject {
    struct Snapshot {
        let id: String
        let title: String
        let html: String
    }

    @Published var title: String
    @Published var html: String

    private var snapshots: [String: Snapshot] = [:]

    init(title: String = "Bob's View", html: String = "") {
        self.title = title
        self.html = html
    }

    static func presentationID(title: String, html: String) -> String {
        "\(title)\u{001F}\(html)".sha256HexDigest()
    }

    func storePresentation(title: String, html: String) -> String {
        let id = Self.presentationID(title: title, html: html)
        snapshots[id] = Snapshot(id: id, title: title, html: html)
        return id
    }

    @discardableResult
    func activatePresentation(id: String) -> Bool {
        guard let snapshot = snapshots[id] else { return false }
        title = snapshot.title
        html = snapshot.html
        return true
    }
}

private extension String {
    func sha256HexDigest() -> String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
