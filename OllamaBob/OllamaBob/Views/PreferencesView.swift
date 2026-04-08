import SwiftUI

struct PreferencesView: View {

    // MARK: Style Constants

    private static let phosphorGreen = Color(red: 0.22, green: 1.0,  blue: 0.08)
    private static let bgBlack       = Color(red: 0.04, green: 0.05, blue: 0.04)
    private static let bgPanel       = Color(red: 0.10, green: 0.11, blue: 0.10)
    private static let textGrey      = Color(white: 0.50)

    // MARK: State

    @ObservedObject var settings = AppSettings.shared

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(PreferencesView.phosphorGreen.opacity(0.3))
            toggleRows
            Spacer()
            footer
        }
        .frame(width: 480, height: 340)
        .background(PreferencesView.bgBlack)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("OllamaBob Preferences")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .foregroundColor(PreferencesView.phosphorGreen)
            Text("Configure your local Bob assistant")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(PreferencesView.textGrey)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var toggleRows: some View {
        VStack(spacing: 1) {
            toggleRow(
                title: "Show Bob",
                subtitle: "Display Bob and his speech bubbles at the top of the chat",
                isOn: $settings.showBob,
                dimmed: false
            )
            sliderRow(
                title: "Chat window transparency",
                subtitle: "Lower values let your desktop show through",
                value: $settings.chatWindowOpacity,
                range: 0.4...1.0
            )
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        Text("v1.0.2  \u{2022}  localhost:11434")
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(PreferencesView.phosphorGreen.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 14)
    }

    // MARK: Row Builder

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        dimmed: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(PreferencesView.phosphorGreen)
                .labelsHidden()
                .disabled(dimmed)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
        .opacity(dimmed ? 0.4 : 1.0)
    }

    private func sliderRow(
        title: String,
        subtitle: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.textGrey)
            }
            HStack(spacing: 12) {
                Slider(value: value, in: range)
                    .tint(PreferencesView.phosphorGreen)
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(PreferencesView.phosphorGreen)
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(PreferencesView.bgPanel)
    }
}
