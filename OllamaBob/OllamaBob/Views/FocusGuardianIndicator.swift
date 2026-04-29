import SwiftUI

/// Standalone indicator showing Focus Guardian status.
///
/// Displays the last frontmost bundle ID, the last persona swap reason, and
/// a lock toggle button. Mounted by the desk status strip and reusable elsewhere.
struct FocusGuardianIndicator: View {

    @ObservedObject private var focusService = FocusService.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: focusGuardianIcon)
                    .foregroundStyle(indicatorColor)
                    .imageScale(.small)

                Text(focusGuardianLabel)
                    .font(.caption)
                    .foregroundStyle(.primary)

                Spacer()

                lockToggleButton
            }

            if let reason = focusService.lastSwapReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Sub-views

    private var lockToggleButton: some View {
        Button {
            focusService.setManualLock(!focusService.manualLockEnabled)
        } label: {
            Label(
                focusService.manualLockEnabled ? "Locked" : "Auto",
                systemImage: focusService.manualLockEnabled ? "lock.fill" : "lock.open"
            )
            .font(.caption2)
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(focusService.manualLockEnabled
              ? "Focus Guardian is locked — tap to resume auto-switching"
              : "Tap to lock the current persona and disable auto-switching")
    }

    // MARK: - Helpers

    private var focusGuardianIcon: String {
        guard settings.focusGuardianEnabled else { return "eye.slash" }
        return focusService.manualLockEnabled ? "lock.fill" : "eye"
    }

    private var indicatorColor: Color {
        guard settings.focusGuardianEnabled else { return .secondary }
        return focusService.manualLockEnabled ? .orange : .green
    }

    private var focusGuardianLabel: String {
        guard settings.focusGuardianEnabled else { return "Focus Guardian: Off" }
        if focusService.manualLockEnabled { return "Locked" }
        if let bundleID = focusService.lastFrontmostBundleID {
            // Show just the last component of the bundle ID for brevity.
            return bundleID.components(separatedBy: ".").last ?? bundleID
        }
        return "Focus Guardian: Watching"
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        FocusGuardianIndicator()
            .frame(width: 280)
    }
    .padding()
}
#endif
