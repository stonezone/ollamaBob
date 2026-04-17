import SwiftUI

/// Reusable search bar with phosphor-green accent to match the terminal colour scheme.
struct ConversationSearchBar: View {
    @Binding var query: String

    private static let phosphorGreen = Color(red: 0.22, green: 1.0, blue: 0.08)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(query.isEmpty ? .secondary : Self.phosphorGreen)
                .font(.system(size: 12))

            TextField("Search chats…", text: $query)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .accentColor(Self.phosphorGreen)

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(query.isEmpty ? Color(.separatorColor) : Self.phosphorGreen.opacity(0.6),
                                lineWidth: 1)
                )
        )
    }
}
