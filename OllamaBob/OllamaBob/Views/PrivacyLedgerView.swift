import SwiftUI

/// Privacy Ledger — shows what Bob has changed (side-effects only).
/// Read-only tool calls are never recorded and will never appear here.
struct PrivacyLedgerView: View {

    // MARK: Style (matches PreferencesView palette)

    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.50)
    private static let errorRed      = Color(red: 1.0, green: 0.30, blue: 0.25)

    // MARK: Date Filter

    enum DateRange: String, CaseIterable, Identifiable {
        case lastHour   = "Last hour"
        case last24h    = "Last 24h"
        case last7days  = "Last 7 days"
        case all        = "All"
        var id: String { rawValue }
    }

    // MARK: State

    @State private var entries: [ExecutionLogEntry] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var dateRange: DateRange = .last24h
    @State private var toolFilter: String = "All"

    // MARK: Derived

    private var filteredEntries: [ExecutionLogEntry] {
        guard toolFilter != "All" else { return entries }
        return entries.filter { $0.toolName == toolFilter }
    }

    private var availableTools: [String] {
        let names = Array(Set(entries.map { $0.toolName })).sorted()
        return ["All"] + names
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock
            filterBar
            Divider()
                .background(Self.phosphorGreen.opacity(0.15))
                .padding(.horizontal, 24)
            entryList
        }
        .onAppear { reload() }
    }

    // MARK: Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What Bob Did")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundColor(Self.phosphorGreen)
            Text("Side-effects only (writes, moves, downloads, calls). Read-only tool calls are not logged.")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Self.textGrey)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Date range
            Picker("", selection: $dateRange) {
                ForEach(DateRange.allCases) { range in
                    Text(range.rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
            .onChange(of: dateRange) { reload() }

            // Tool filter
            Picker("", selection: $toolFilter) {
                ForEach(availableTools, id: \.self) { tool in
                    Text(tool)
                        .font(.system(.caption, design: .monospaced))
                        .tag(tool)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Spacer()

            // Refresh
            Button(action: reload) {
                Text(isLoading ? "Loading…" : "Refresh")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(isLoading ? Self.textGrey : Self.phosphorGreen)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    // MARK: Entry List

    private var entryList: some View {
        Group {
            if let error = loadError {
                Text("Error: \(error)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.errorRed)
                    .padding(24)
            } else if filteredEntries.isEmpty {
                Text(isLoading ? "Loading…" : "No entries for the selected filters.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.textGrey)
                    .padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredEntries) { entry in
                            entryRow(entry)
                            Divider()
                                .background(Self.phosphorGreen.opacity(0.08))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: Entry Row

    private func entryRow(_ entry: ExecutionLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Success / failure indicator
            Text(entry.success ? "✓" : "✗")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(entry.success ? Self.phosphorGreen : Self.errorRed)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(entry.toolName)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundColor(.white)
                    Text(relativeTime(entry.timestamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Self.textGrey)
                    Text("\(entry.durationMs)ms")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Self.textGrey)
                }
                Text(entry.summary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Self.textGrey)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Helpers

    private func reload() {
        isLoading = true
        loadError = nil
        let since = since(for: dateRange)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let rows = try DatabaseManager.shared.fetchExecutionLog(since: since, until: nil, limit: 500)
                DispatchQueue.main.async {
                    entries = rows
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func since(for range: DateRange) -> Date? {
        let now = Date()
        switch range {
        case .lastHour:  return now.addingTimeInterval(-3_600)
        case .last24h:   return now.addingTimeInterval(-86_400)
        case .last7days: return now.addingTimeInterval(-7 * 86_400)
        case .all:       return nil
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60      { return "\(Int(diff))s ago" }
        if diff < 3_600   { return "\(Int(diff / 60))m ago" }
        if diff < 86_400  { return "\(Int(diff / 3_600))h ago" }
        return "\(Int(diff / 86_400))d ago"
    }
}
