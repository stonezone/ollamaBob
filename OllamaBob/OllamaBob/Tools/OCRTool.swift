import Foundation
import AppKit
import Vision
import CoreImage

/// OCR utility backed by Apple's Vision framework.
enum OCRTool {
    private static let maxOutputChars = 10_000

    static func execute(path: String?) async -> ToolResult {
        let start = Date()

        guard let cgImage = loadImage(path: path) else {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            if let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
                return .failure(tool: "ocr", error: "Could not load image at \(rawPath).", durationMs: durationMs)
            }
            return .failure(tool: "ocr", error: "Clipboard does not contain an image.", durationMs: durationMs)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage)
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            let text = lines.isEmpty ? "(no text found in image)" : lines.joined(separator: "\n")
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .success(
                tool: "ocr",
                content: OutputLimits.truncate(text, max: maxOutputChars),
                durationMs: durationMs
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            return .failure(tool: "ocr", error: error.localizedDescription, durationMs: durationMs)
        }
    }

    private static func loadImage(path: String?) -> CGImage? {
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedPath.isEmpty {
            return loadClipboardImage()
        }

        guard let image = NSImage(contentsOfFile: trimmedPath) else {
            return nil
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func loadClipboardImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType.tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return cgImage
                }
            }
        }

        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType.pdf),
           let image = NSImage(data: data) {
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        return nil
    }
}
