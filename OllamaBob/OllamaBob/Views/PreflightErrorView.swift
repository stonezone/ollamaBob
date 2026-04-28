import SwiftUI

struct PreflightErrorView: View {
    let status: PreflightStatus
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Bob can't start yet")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                if !status.ollamaReachable {
                    errorRow(
                        icon: "server.rack",
                        title: "Ollama not running",
                        fix: "Start Ollama and relaunch the app"
                    )
                }

                if status.ollamaReachable && !status.modelInstalled {
                    errorRow(
                        icon: "cpu",
                        title: "Model not installed",
                        fix: "Run: ollama pull \(status.requiredModelName)"
                    )
                }

                if !status.databaseWritable {
                    errorRow(
                        icon: "externaldrive.badge.xmark",
                        title: "Database not writable",
                        fix: "Check disk permissions"
                    )
                }

                if !status.sandboxDisabled {
                    errorRow(
                        icon: "lock.shield",
                        title: "App Sandbox is enabled",
                        fix: "Disable App Sandbox in Xcode project settings"
                    )
                }

                if !status.braveKeyPresent {
                    infoRow(
                        icon: "magnifyingglass",
                        title: "Brave Search not configured",
                        note: "Web search will be disabled. Set BRAVE_API_KEY to enable."
                    )
                }

                if status.jarvisPhoneEnabled && (!status.jarvisAPIKeyPresent || !status.jarvisOperatorSecretPresent) {
                    infoRow(
                        icon: "phone.badge.exclamationmark",
                        title: "Jarvis phone secrets incomplete",
                        note: "Phone integration is enabled, but Bob cannot talk to the local Jarvis daemon until both the Jarvis API key and operator secret are configured."
                    )
                }
            }

            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 350)
    }

    private func errorRow(icon: String, title: String, fix: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.bold())
                Text(fix).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func infoRow(icon: String, title: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.yellow)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(note).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
