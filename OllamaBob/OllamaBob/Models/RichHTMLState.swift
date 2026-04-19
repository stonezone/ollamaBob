import Foundation
import Combine

@MainActor
final class RichHTMLState: ObservableObject {
    @Published var title: String
    @Published var html: String

    init(title: String = "Bob's View", html: String = "") {
        self.title = title
        self.html = html
    }
}
