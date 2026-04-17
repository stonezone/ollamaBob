import AppKit

enum BobSounds {
    @MainActor
    static func playSend() {
        guard AppSettings.shared.soundsEnabled else { return }
        NSSound(named: NSSound.Name("Tink"))?.play()
    }

    @MainActor
    static func playReceive() {
        guard AppSettings.shared.soundsEnabled else { return }
        NSSound(named: NSSound.Name("Pop"))?.play()
    }
}
