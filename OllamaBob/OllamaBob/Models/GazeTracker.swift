import Foundation
import AppKit
import Combine

/// Publishes the cursor's location inside the active OllamaBob window so
/// SwiftUI persona views can drive their pupil offset without each scene
/// installing its own NSEvent monitor.
///
/// The monitor only fires while the app is frontmost; ambient gaze when the
/// app is in the background would require accessibility permissions, which
/// is more friction than the feature is worth.
@MainActor
final class GazeTracker: ObservableObject {
    static let shared = GazeTracker()

    /// Cursor position in the active window's coordinate space (origin at
    /// bottom-left, y growing up — AppKit convention). `nil` when no
    /// cursor sample has been captured yet.
    @Published private(set) var cursorInWindow: CGPoint?

    private var monitor: Any?

    private init() {
        startMonitoring()
    }

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            guard let self else { return event }
            // NSEvent.locationInWindow uses AppKit's bottom-left origin; SwiftUI's
            // GeometryProxy.frame(in: .global) gives top-left origin within the
            // host window's contentView. Flip Y so consumers can compare directly.
            let raw = event.locationInWindow
            let flipped: CGPoint
            if let contentHeight = event.window?.contentView?.frame.height {
                flipped = CGPoint(x: raw.x, y: contentHeight - raw.y)
            } else {
                flipped = raw
            }
            Task { @MainActor in
                self.cursorInWindow = flipped
            }
            return event
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
