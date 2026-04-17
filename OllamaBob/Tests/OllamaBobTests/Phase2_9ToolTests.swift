import XCTest
import AppKit
@testable import OllamaBob

final class Phase2_9ToolTests: XCTestCase {
    // MARK: - Approval classification

    func testApprovalPolicyClassifiesPhase2_9Tools() {
        XCTAssertEqual(ApprovalPolicy.check(toolName: "ocr", arguments: [:]), .none)
        XCTAssertEqual(ApprovalPolicy.check(toolName: "speak", arguments: ["text": "hi"]), .none)
        XCTAssertEqual(ApprovalPolicy.check(toolName: "weather", arguments: ["location": "HNL"]), .none)
        XCTAssertEqual(ApprovalPolicy.check(toolName: "unit_convert", arguments: ["from": "1 mi", "to": "km"]), .none)
        XCTAssertEqual(
            ApprovalPolicy.check(
                toolName: "image_convert",
                arguments: ["input_path": "/tmp/a.png", "output_path": "/tmp/b.jpg", "format": "jpeg"]
            ),
            .modal
        )
        XCTAssertEqual(ApprovalPolicy.check(toolName: "youtube_search", arguments: ["query": "foo"]), .none)
        XCTAssertEqual(
            ApprovalPolicy.check(
                toolName: "youtube_download",
                arguments: ["url": "https://youtube.com/watch?v=x", "format": "mp3"]
            ),
            .modal
        )
    }

    // MARK: - OCR

    func testOCRExtractsTextFromGeneratedImage() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try writeTestImage(text: "HELLO BOB", to: fileURL)

        let result = await OCRTool.execute(path: fileURL.path)
        XCTAssertTrue(result.success, result.content)
        XCTAssertTrue(result.content.uppercased().contains("HELLO"), result.content)
        XCTAssertTrue(result.content.uppercased().contains("BOB"), result.content)
    }

    // MARK: - Speak

    func testSpeakReturnsQuickly() async {
        let result = await SayTool.execute(text: "test", voice: nil)
        XCTAssertTrue(result.success, result.content)
        XCTAssertLessThan(result.durationMs, 2_000, "speak should return quickly")
    }

    // MARK: - Weather

    func testWeatherRejectsEmptyLocation() async {
        let result = await WeatherTool.execute(location: "   ")
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Location is empty."))
    }

    func testWeatherURLConstructionEncodesLocation() {
        let location = "Honolulu, HI"
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        XCTAssertEqual(encoded, "Honolulu,%20HI")
        XCTAssertEqual("https://wttr.in/\(encoded ?? "")?format=3", "https://wttr.in/Honolulu,%20HI?format=3")
    }

    // MARK: - Units

    func testUnitConvertMilesToKilometers() async {
        let result = await UnitsTool.execute(from: "5 miles", to: "kilometers")
        XCTAssertTrue(result.success, result.content)

        let numericPart = result.content.split(separator: "=", maxSplits: 1).last.map(String.init) ?? result.content
        let pattern = #"[0-9]+(?:\.[0-9]+)?"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(numericPart.startIndex..., in: numericPart)
        guard let match = regex?.firstMatch(in: numericPart, range: nsRange),
              let range = Range(match.range, in: numericPart),
              let value = Double(numericPart[range]) else {
            XCTFail("Expected numeric conversion output, got: \(result.content)")
            return
        }

        XCTAssertGreaterThan(value, 8.0)
        XCTAssertLessThan(value, 8.1)
    }

    // MARK: - image_convert

    func testSipsRejectsInvalidFormat() async {
        let result = await SipsTool.execute(
            inputPath: "/tmp/a.png",
            outputPath: "/tmp/b.xyz",
            format: "xyz",
            maxDimension: nil
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Unsupported format"))
    }

    func testSipsConvertsPNGToJPEG() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputURL = dir.appendingPathComponent("in.png")
        let outputURL = dir.appendingPathComponent("out.jpg")
        try writeTinyPNG(to: inputURL)

        let result = await SipsTool.execute(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            format: "jpeg",
            maxDimension: nil
        )
        XCTAssertTrue(result.success, result.content)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = attrs[.size] as? NSNumber
        XCTAssertGreaterThan(size?.intValue ?? 0, 0)
    }

    // MARK: - youtube_download

    func testYouTubeDownloadRejectsEmptyURL() async {
        let result = await YouTubeTool.download(url: "   ", format: "mp3", outputDir: nil)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("URL is empty"))
    }

    func testYouTubeDownloadRejectsNonYouTubeURL() async {
        let result = await YouTubeTool.download(url: "https://example.com/video.mp4", format: "mp3", outputDir: nil)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("YouTube"))
    }

    func testYouTubeDownloadRejectsMissingFormat() async {
        let result = await YouTubeTool.download(url: "https://youtube.com/watch?v=abc", format: "", outputDir: nil)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Unsupported format"))
    }

    func testYouTubeDownloadRejectsInvalidFormat() async {
        let result = await YouTubeTool.download(url: "https://youtube.com/watch?v=abc", format: "wav", outputDir: nil)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.content.contains("Unsupported format"))
    }

    private func writeTestImage(text: String, to url: URL) throws {
        let size = NSSize(width: 800, height: 220)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let drawRect = NSRect(x: 24, y: 60, width: size.width - 48, height: size.height - 120)
        NSString(string: text).draw(in: drawRect, withAttributes: attrs)
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Phase2_9ToolTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try pngData.write(to: url)
    }

    private func writeTinyPNG(to url: URL) throws {
        let width = 2
        let height = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "Phase2_9ToolTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap"])
        }

        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(.systemBlue, atX: x, y: y)
            }
        }

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Phase2_9ToolTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to encode tiny PNG"])
        }
        try pngData.write(to: url)
    }
}
