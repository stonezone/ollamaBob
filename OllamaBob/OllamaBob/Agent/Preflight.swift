import Foundation

struct PreflightStatus {
    var ollamaReachable: Bool = false
    var modelInstalled: Bool = false
    var braveKeyPresent: Bool = false
    var databaseWritable: Bool = false
    var sandboxDisabled: Bool = false

    var canLaunch: Bool {
        ollamaReachable && modelInstalled && databaseWritable && sandboxDisabled
    }
}

enum Preflight {
    static func run() async -> PreflightStatus {
        var status = PreflightStatus()
        let client = OllamaClient()

        // 1. Ollama reachable
        status.ollamaReachable = await client.isReachable()

        // 2. Model installed
        if status.ollamaReachable {
            let models = await client.installedModels()
            status.modelInstalled = models.contains(where: { name in
                name.hasPrefix(AppConfig.primaryModel) || name.hasPrefix(AppConfig.fallbackModel)
            })
        }

        // 3. Brave API key present (optional)
        status.braveKeyPresent = !AppConfig.braveAPIKey.isEmpty

        // 4. Database writable (DatabaseManager is already initialized by AppState)
        status.databaseWritable = DatabaseManager.shared.canWrite()

        // 5. Sandbox disabled (SPM-built executables don't have sandbox by default)
        status.sandboxDisabled = !ProcessInfo.processInfo.environment.keys.contains("APP_SANDBOX_CONTAINER_ID")

        return status
    }

}
