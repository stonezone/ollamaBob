import Foundation
import Combine

// MARK: - Thread-safe backing store (module-internal)

/// NSLock-protected box that holds the current dev-mode repo root.
/// This is the source of truth for `ApprovalPolicy.check`, which must read
/// from any actor without a MainActor hop.
///
/// Only `DevModeStore` should write to this. Reads are open.
final class DevModeStorage: @unchecked Sendable {
    static let shared = DevModeStorage()

    private var value: String?
    private let lock = NSLock()

    private init() {}

    func get() -> String? {
        lock.withLock { value }
    }

    func set(_ newValue: String?) {
        lock.withLock { value = newValue }
    }
}

// MARK: - ObservableObject for SwiftUI / tool execution

/// Process-scoped in-memory singleton that tracks whether Code Companion
/// dev_mode is active for the current session.
///
/// Design notes:
/// - Intentionally NOT persisted to UserDefaults or disk. Dev mode must
///   be re-enabled per session so the user explicitly opts in each time.
/// - `repoRoot` is a `@Published` property on `@MainActor` for SwiftUI
///   observation. Writing from tool execution (which is @MainActor) is safe.
/// - `DevModeStorage.shared.get()` provides a nonisolated thread-safe read
///   used by `ApprovalPolicy.check`. Both stores are kept in sync via `didSet`.
@MainActor
final class DevModeStore: ObservableObject {
    static let shared = DevModeStore()

    /// Absolute, standardized path to the active dev-mode repo root.
    /// `nil` means dev mode is off. Writes synchronize to `DevModeStorage`.
    @Published var repoRoot: String? {
        didSet { DevModeStorage.shared.set(repoRoot) }
    }

    private init() {}
}
