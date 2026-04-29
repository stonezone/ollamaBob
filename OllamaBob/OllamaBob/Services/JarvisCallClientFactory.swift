import Foundation

// MARK: - JarvisCallClientFactory
// Returns the correct JarvisCallClient implementation at runtime.
// In DEBUG builds, honours the AppSettings.useMockedJarvisClient toggle.
// In release builds, always returns JarvisCallClientHTTP.

@MainActor
enum JarvisCallClientFactory {
    static func current() -> any JarvisCallClient {
#if DEBUG
        if AppSettings.shared.useMockedJarvisClient {
            return JarvisCallClientMock.shared
        }
#endif
        return JarvisCallClientHTTP()
    }
}
