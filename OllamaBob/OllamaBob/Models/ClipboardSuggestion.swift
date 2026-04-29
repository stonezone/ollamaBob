import Foundation

/// A suggestion produced by `ClipboardClassifier` after a clipboard change.
///
/// Equatable so `ClipboardWatcher` can avoid re-publishing the same suggestion
/// when the clipboard content hasn't meaningfully changed.
struct ClipboardSuggestion: Equatable {
    enum Kind: Equatable {
        case messyURL
        case messyJSON
        case base64Blob
        case stackTrace
        case generic
    }

    let kind: Kind
    /// First 80 characters of the clipboard payload, for chip display.
    let preview: String
    let detectedAt: Date

    static func == (lhs: ClipboardSuggestion, rhs: ClipboardSuggestion) -> Bool {
        lhs.kind == rhs.kind && lhs.preview == rhs.preview
    }
}

extension ClipboardSuggestion.Kind {
    /// Short human-readable label used on the chip button.
    var chipLabel: String {
        switch self {
        case .messyURL:   return "Clean URL"
        case .messyJSON:  return "Pretty-print JSON"
        case .base64Blob: return "Decode base64"
        case .stackTrace: return "Summarize stack trace"
        case .generic:    return "Clean clipboard"
        }
    }

    var chipIcon: String {
        switch self {
        case .messyURL:   return "link.badge.plus"
        case .messyJSON:  return "curlybraces"
        case .base64Blob: return "lock.open"
        case .stackTrace: return "ladybug"
        case .generic:    return "scissors"
        }
    }
}
