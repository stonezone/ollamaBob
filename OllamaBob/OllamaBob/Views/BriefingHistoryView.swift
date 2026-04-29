import SwiftUI

/// Briefing History — displays past Daily Briefing run summaries.
/// Display-only. Follows the Privacy Ledger visual style.
struct BriefingHistoryView: View {

    // MARK: - Style (matches PreferencesView / PrivacyLedgerView palette)

    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.50)
    private static let errorRed      = Color(red: 1.0, green: 0.30, blue: 0.25)

    // MARK: - State

    @State private var briefings: [BriefingResult] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var expandedID: Int64?

    // MARK: - Date formatter

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
            Divider()
                .background(Self.phosphorGreen.opacity(0.15))
                .padding(.horizontal, 24)
            resultList
        }
        .background(Self.bgBlack)
        .onAppear { reload() }
    }

    // MARK: - Header

    private var headerBlock: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Briefing History")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(Self.phosphorGreen)
                Text("\(briefings.count) run(s) stored")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Self.textGrey)
            }
            Spacer()
            Button("Refresh") { reload() }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Self.phosphorGreen)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - List

    private var resultList: some View {
        Group {
            if isLoading {
                ProgressView()
                    .padding()
                    .frame(maxWidth: .infinity)
            } else if let err = loadError {
                Text(err)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Self.errorRed)
                    .padding()
            } else if briefings.isEmpty {
                Text("No briefings yet. Enable Daily Briefing in Preferences.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Self.textGrey)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(briefings, id: \.id) { briefing in
                            briefingRow(briefing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Row

    private func briefingRow(_ briefing: BriefingResult) -> some View {
        let isExpanded = expandedID == briefing.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Success/failure indicator
                Circle()
                    .fill(briefing.success ? Self.phosphorGreen : Self.errorRed)
                    .frame(width: 7, height: 7)

                Text(Self.formatter.string(from: briefing.runAt))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Self.phosphorGreen)

                Spacer()

                Text(isExpanded ? "Hide" : "Show")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Self.textGrey)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedID = isExpanded ? nil : briefing.id
                }
            }

            if isExpanded {
                Text(briefing.summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(8)
                    .background(Self.bgPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(10)
        .background(Self.bgPanel.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Load

    private func reload() {
        isLoading = true
        loadError = nil
        Task {
            do {
                let rows = try DatabaseManager.shared.fetchRecentBriefings(limit: 100)
                await MainActor.run {
                    briefings = rows
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = "Load failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}
