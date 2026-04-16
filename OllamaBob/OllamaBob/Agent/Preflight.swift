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
    static func run(
        clientReachable: @escaping () async -> Bool = {
            await OllamaClient().isReachable()
        },
        installedModels: @escaping () async -> [String] = {
            await OllamaClient().installedModels()
        },
        braveKeyPresent: Bool = !AppConfig.braveAPIKey.isEmpty,
        databaseWritable: () -> Bool = {
            DatabaseManager.shared.canWrite()
        },
        sandboxDisabled: () -> Bool = {
            !ProcessInfo.processInfo.environment.keys.contains("APP_SANDBOX_CONTAINER_ID")
        }
    ) async -> PreflightStatus {
        var status = PreflightStatus()

        // 1. Ollama reachable
        status.ollamaReachable = await clientReachable()

        // 2. Model installed
        if status.ollamaReachable {
            let models = await installedModels()
            status.modelInstalled = models.contains(where: { name in
                name.hasPrefix(AppConfig.primaryModel) || name.hasPrefix(AppConfig.fallbackModel)
            })
        }

        // 3. Brave API key present (optional)
        status.braveKeyPresent = braveKeyPresent

        // 4. Database writable (DatabaseManager is already initialized by AppState)
        status.databaseWritable = databaseWritable()

        // 5. Sandbox disabled (SPM-built executables don't have sandbox by default)
        status.sandboxDisabled = sandboxDisabled()

        return status
    }
}
