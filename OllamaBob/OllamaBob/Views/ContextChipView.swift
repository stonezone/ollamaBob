import SwiftUI

/// A small chip that shows the most recent Mac context capture.
/// Observes `MacContextStore.shared` and hides itself when no context
/// has been captured yet or after the user dismisses it.
///
/// NOT yet wired into `BobsDeskView` — it is ready to drop in during
/// Phase 8 when the desk UI is refactored. Place it wherever the desk
/// view's input row is assembled.
///
/// Renders: app icon (SF symbol fallback) + localized app name +
/// window title snippet + Finder selection count + OCR snippet length.
/// Uses monospaced caption font and the phosphorGreen accent colour that
/// matches the existing Bob palette.
struct ContextChipView: View {

    @StateObject private var store = MacContextStore.shared

    var body: some View {
        if let ctx = store.lastContext {
            chip(for: ctx)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .animation(.easeInOut(duration: 0.18), value: store.lastContext != nil)
        }
    }

    // MARK: - Chip body

    @ViewBuilder
    private func chip(for ctx: MacContext) -> some View {
        HStack(spacing: 6) {
            // App icon / name
            HStack(spacing: 4) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(ctx.activeApp?.localizedName ?? "Mac")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
            }

            // Window title
            if let title = ctx.activeApp?.windowTitle, !title.isEmpty {
                Divider()
                    .frame(height: 10)
                    .opacity(0.4)
                Text(title)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Color.accentColor.opacity(0.8))
                    .lineLimit(1)
                    .frame(maxWidth: 160, alignment: .leading)
            }

            // Finder selection count
            if let items = ctx.selectedItems, !items.isEmpty {
                Divider()
                    .frame(height: 10)
                    .opacity(0.4)
                HStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8, weight: .regular))
                    Text("Selected: \(items.count)")
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundColor(Color.accentColor.opacity(0.75))
            }

            // OCR snippet info
            if let snippet = ctx.screenOCRSnippet, !snippet.isEmpty {
                Divider()
                    .frame(height: 10)
                    .opacity(0.4)
                HStack(spacing: 3) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 8, weight: .regular))
                    Text("OCR'd \(snippet.count) chars")
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundColor(Color.accentColor.opacity(0.75))
            }

            Spacer(minLength: 0)

            // Dismiss button
            Button {
                MacContextStore.shared.clear()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.accentColor.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Clear Mac context snapshot")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.09))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 0.7)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Context chip — active") {
    let store = MacContextStore.shared
    let ctx = MacContext(
        capturedAt: Date(),
        activeApp: MacContext.ActiveApp(
            bundleIdentifier: "com.apple.Xcode",
            localizedName: "Xcode",
            windowTitle: "OllamaBob — MacContextService.swift"
        ),
        selectedItems: ["/Users/zack/Downloads/photo.jpg", "/Users/zack/Downloads/doc.pdf"],
        clipboardMeta: MacContext.ClipboardMeta(length: 420, preview: "Hello Bob", isText: true),
        screenOCRSnippet: "import Foundation\nimport AppKit"
    )
    Task { @MainActor in store.update(ctx) }
    return ContextChipView()
        .padding()
        .frame(width: 480)
}
#endif
