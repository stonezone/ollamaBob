import SwiftUI

/// Ready-to-drop badge that shows when Code Companion dev mode is active.
///
/// Usage: drop `DevModeIndicator()` anywhere in a SwiftUI view hierarchy.
/// It only renders when `DevModeStore.shared.repoRoot != nil`, so it is
/// invisible in normal operation.
///
/// The view is intentionally NOT integrated into BobsDeskView in Phase 6 —
/// it is shipped ready-to-use for a future layout integration.
struct DevModeIndicator: View {
    @ObservedObject private var store = DevModeStore.shared

    var body: some View {
        if let root = store.repoRoot {
            let repoName = URL(fileURLWithPath: root).lastPathComponent
            HStack(spacing: 4) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                Text("Dev mode: \(repoName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
            )
            .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
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
