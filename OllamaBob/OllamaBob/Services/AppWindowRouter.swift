import SwiftUI

@MainActor
final class AppWindowRouter {
    static let shared = AppWindowRouter()

    static let richHTMLID = "rich-html"
    static let toolActivityID = "tool-activity"
    static let preferencesID = "preferences"
    static let onboardingID = "onboarding"

    private var openWindowHandler: ((String) -> Void)?

    private init() {}

    func register(openWindowHandler: @escaping (String) -> Void) {
        self.openWindowHandler = openWindowHandler
    }

    func open(id: String) {
        openWindowHandler?(id)
    }
}
