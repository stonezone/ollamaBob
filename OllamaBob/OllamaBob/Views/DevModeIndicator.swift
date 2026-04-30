import SwiftUI

/// Ready-to-drop badge that shows when Code Companion dev mode is active.
///
/// Usage: drop `DevModeIndicator()` anywhere in a SwiftUI view hierarchy.
/// It only renders when `DevModeStore.shared.repoRoot != nil`, so it is
/// invisible in normal operation.
///
/// The desk status strip mounts this view when Code Companion mode is active.
struct DevModeIndicator: View {
    @ObservedObject private var store = DevModeStore.shared

    var body: some View {
        if let root = store.repoRoot {
            let repoName = URL(fileURLWithPath: root).lastPathComponent
            BobChip(
                label: "Dev mode: \(repoName)",
                tint: BobColors.Accent.bobBlue,
                isProminent: true
            ) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BobColors.Text.onGlass)
            }
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        DevModeIndicator()
            .onAppear {
                Task { @MainActor in
                    DevModeStore.shared.repoRoot = "/Users/dev/myproject"
                }
            }
        Text("(badge visible when dev mode is active)")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .frame(width: 320)
}
#endif
