import Foundation
import CryptoKit

struct DetectedArtifact: Identifiable, Equatable {
    let kind: PresentationKind
    let content: String
    let title: String?
    let label: String
    let systemImage: String

    var id: String {
        "\(kind.rawValue)\u{001F}\(content)\u{001F}\(title ?? "")".sha256HexDigest()
    }
}

enum ArtifactDetector {
    private final class ArtifactArrayBox: NSObject {
        let artifacts: [DetectedArtifact]

        init(_ artifacts: [DetectedArtifact]) {
            self.artifacts = artifacts
        }
    }

    private static let detectionCache: NSCache<NSString, ArtifactArrayBox> = {
        let cache = NSCache<NSString, ArtifactArrayBox>()
        cache.countLimit = 512
        return cache
    }()

    static func detect(in text: String) -> [DetectedArtifact] {
        let cacheKey = text as NSString
        if let cached = detectionCache.object(forKey: cacheKey) {
            return cached.artifacts
        }

        let masked = maskingCode(in: text)

        let markdownImageMatches = matches(regex: markdownImageRegex, in: masked)
        let markdownLinkMatches = matches(regex: markdownLinkRegex, in: masked)

        var artifacts: [DetectedArtifact] = []
        var seen = Set<String>()
        var consumedMatches: [Match] = []

        for match in markdownImageMatches {
            guard match.captures.count >= 2 else { continue }
            let alt = match.captures[0]
            let target = match.captures[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let artifact: DetectedArtifact
            if looksLikeLocalPath(target) {
                artifact = DetectedArtifact(
                    kind: .file,
                    content: target,
                    title: alt.isEmpty ? nil : alt,
                    label: labelForFile(target),
                    systemImage: imageForFile(target)
                )
            } else if let url = normalizedRemoteURL(target) {
                artifact = DetectedArtifact(
                    kind: .url,
                    content: url,
                    title: alt.isEmpty ? nil : alt,
                    label: "Open image in browser",
                    systemImage: "photo"
                )
            } else {
                continue
            }

            if seen.insert(artifact.id).inserted {
                artifacts.append(artifact)
            }
            consumedMatches.append(match)
        }

        for match in markdownLinkMatches {
            guard match.captures.count >= 2 else { continue }
            let text = match.captures[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = normalizedRemoteURL(match.captures[1]) else { continue }

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
            consumedMatches.append(match)
        }

        let bareURLScanText = blanking(matchRanges: consumedMatches, in: masked)
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

        detectionCache.setObject(ArtifactArrayBox(artifacts), forKey: cacheKey)
        return artifacts
    }

    private struct Match {
        let range: NSRange
        let captures: [String]
    }

    private static let markdownImageRegex = try? NSRegularExpression(
        pattern: #"\!\[([^\]]*)\]\(([^)\n]+)\)"#,
        options: [.caseInsensitive]
    )

    private static let markdownLinkRegex = try? NSRegularExpression(
        pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#,
        options: [.caseInsensitive]
    )

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func matches(regex: NSRegularExpression?, in text: String) -> [Match] {
        guard let regex else { return [] }
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
        guard let linkDetector else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return linkDetector.matches(in: text, range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return url.absoluteString
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
        string.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?:;)]}'\""))
    }

    private static func normalizedRemoteURL(_ candidate: String) -> String? {
        let trimmed = trimmingTrailingPunctuation(from: candidate.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return trimmed
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

private extension String {
    func sha256HexDigest() -> String {
        let digest = SHA256.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
