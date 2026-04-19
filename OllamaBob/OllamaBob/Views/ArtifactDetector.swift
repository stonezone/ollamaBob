import Foundation

struct DetectedArtifact: Identifiable, Equatable {
    let kind: PresentationKind
    let content: String
    let title: String?
    let label: String
    let systemImage: String

    var id: String {
        "\(kind.rawValue)|\(content)|\(title ?? "")"
    }
}

enum ArtifactDetector {
    static func detect(in text: String) -> [DetectedArtifact] {
        let masked = maskingCode(in: text)

        let markdownImageMatches = matches(
            pattern: #"\!\[([^\]]*)\]\(([^)\n]+)\)"#,
            in: masked
        )
        let markdownLinkMatches = matches(
            pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#,
            in: masked
        )

        var artifacts: [DetectedArtifact] = []
        var seen = Set<String>()

        for match in markdownImageMatches {
            guard match.captures.count >= 2 else { continue }
            let alt = match.captures[0]
            let path = match.captures[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeLocalPath(path) else { continue }

            let artifact = DetectedArtifact(
                kind: .file,
                content: path,
                title: alt.isEmpty ? nil : alt,
                label: labelForFile(path),
                systemImage: imageForFile(path)
            )
            if seen.insert(artifact.id).inserted {
                artifacts.append(artifact)
            }
        }

        for match in markdownLinkMatches {
            guard match.captures.count >= 2 else { continue }
            let text = match.captures[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let url = match.captures[1].trimmingCharacters(in: .whitespacesAndNewlines)

            let artifact = DetectedArtifact(
                kind: .url,
                content: url,
                title: text.isEmpty ? nil : text,
                label: "Open in browser",
                systemImage: "link"
            )
            if seen.insert(artifact.id).inserted {
                artifacts.append(artifact)
            }
        }

        let bareURLScanText = blanking(matchRanges: markdownImageMatches + markdownLinkMatches, in: masked)
        for rawURL in bareURLs(in: bareURLScanText) {
            let url = trimmingTrailingPunctuation(from: rawURL)
            let artifact = DetectedArtifact(
                kind: .url,
                content: url,
                title: nil,
                label: "Open in browser",
                systemImage: "link"
            )
            if seen.insert(artifact.id).inserted {
                artifacts.append(artifact)
            }
        }

        return artifacts
    }

    private struct Match {
        let range: NSRange
        let captures: [String]
    }

    private static func matches(pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { result in
            var captures: [String] = []
            for captureIndex in 1..<result.numberOfRanges {
                guard let captureRange = Range(result.range(at: captureIndex), in: text) else {
                    captures.append("")
                    continue
                }
                captures.append(String(text[captureRange]))
            }
            return Match(range: result.range, captures: captures)
        }
    }

    private static func maskingCode(in text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var maskedLines: [String] = []
        var inFence = false

        for line in lines {
            let string = String(line)
            if string.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                maskedLines.append("")
                continue
            }

            if inFence {
                maskedLines.append("")
                continue
            }

            maskedLines.append(maskingInlineCode(in: string))
        }

        return maskedLines.joined(separator: "\n")
    }

    private static func maskingInlineCode(in line: String) -> String {
        var result = ""
        var inInlineCode = false

        for character in line {
            if character == "`" {
                inInlineCode.toggle()
                result.append(" ")
            } else if inInlineCode {
                result.append(" ")
            } else {
                result.append(character)
            }
        }

        return result
    }

    private static func blanking(matchRanges: [Match], in text: String) -> String {
        let mutable = NSMutableString(string: text)
        for match in matchRanges.reversed() {
            mutable.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
        }
        return mutable as String
    }

    private static func bareURLs(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bhttps?://[^\s<>\[\]\"`]+"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func looksLikeLocalPath(_ candidate: String) -> Bool {
        let lowercased = candidate.lowercased()
        guard lowercased.hasPrefix("http://") == false,
              lowercased.hasPrefix("https://") == false,
              lowercased.hasPrefix("data:") == false,
              lowercased.hasPrefix("javascript:") == false else {
            return false
        }
        return candidate.hasPrefix("/") || candidate.hasPrefix("~/")
    }

    private static func trimmingTrailingPunctuation(from string: String) -> String {
        string.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;"))
    }

    private static func labelForFile(_ path: String) -> String {
        isImagePath(path) ? "Open in Preview" : "Open"
    }

    private static func imageForFile(_ path: String) -> String {
        isImagePath(path) ? "photo" : "doc"
    }

    private static func isImagePath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"].contains(ext)
    }
}
