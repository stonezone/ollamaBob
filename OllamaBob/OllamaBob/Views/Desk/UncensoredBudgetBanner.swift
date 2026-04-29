import SwiftUI

struct UncensoredBudgetBanner: View {
    let snapshot: ContextBudget.Snapshot

    private var percentText: String {
        "\(Int((snapshot.percent * 100).rounded()))%"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .imageScale(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Uncensored context is \(percentText) full")
                    .font(.caption.weight(.semibold))
                Text("\(snapshot.approxTokens) / \(snapshot.numCtx) approx tokens. Start a fresh chat before details fall out of context.")
                    .font(.caption2)
                    .opacity(0.86)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.black.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(red: 1.0, green: 0.72, blue: 0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.16), lineWidth: 0.8))
        .help("Uncensored mode does not compact automatically.")
    }
}
