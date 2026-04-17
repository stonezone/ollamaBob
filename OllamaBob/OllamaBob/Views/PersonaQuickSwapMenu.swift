import SwiftUI

/// Compact persona badge + popover that lives in BobsDeskView's status area.
/// Tap the badge to open a popover listing all personas; tap one to switch.
struct PersonaQuickSwapMenu: View {

    @ObservedObject private var store = PersonaStore.shared

    var body: some View {
        Menu {
            ForEach(store.personas) { persona in
                Button {
                    store.activePersonaID = persona.id
                } label: {
                    if persona.id == store.activePersonaID {
                        Label(persona.name, systemImage: "checkmark")
                    } else {
                        Text(persona.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text("\u{1F3AD}")          // theatre mask glyph
                    .font(.system(size: 11))
                Text(store.activePersona.name)
                    .font(.system(size: 11, design: .monospaced))
                Text("\u{25BE}")           // down-pointing small triangle
                    .font(.system(size: 9))
            }
            .foregroundColor(BobsDeskView.phosphorGreenPublic)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
