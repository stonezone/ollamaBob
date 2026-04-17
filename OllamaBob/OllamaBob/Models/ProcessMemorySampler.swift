import Foundation

struct ProcessMemorySnapshot: Sendable {
    let bobBytes: Int64?
    let ollamaBytes: Int64?
}

enum ProcessMemorySampler {
    static func sample() async -> ProcessMemorySnapshot {
        async let bob = rssForCurrentProcess()
        async let ollama = rssForOllama()
        return await ProcessMemorySnapshot(
            bobBytes: bob,
            ollamaBytes: ollama
        )
    }

    static func format(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "--" }

        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 {
            return gib >= 10 ? "\(Int(gib.rounded()))G" : String(format: "%.1fG", gib)
        }

        let mib = Double(bytes) / 1_048_576
        if mib >= 100 {
            return "\(Int(mib.rounded()))M"
        }
        return String(format: "%.1fM", mib)
    }

    private static func rssForCurrentProcess() async -> Int64? {
        await rssForPID(ProcessInfo.processInfo.processIdentifier)
    }

    private static func rssForOllama() async -> Int64? {
        // `comm=` truncates to 16 chars on macOS, so paths like
        // `/Applications/Ollama.app/Contents/Resources/ollama` never match a
        // `== "ollama"` test. Use `command=` (full argv) instead and match
        // the executable basename before any arguments.
        let output = await runProcess(
            executable: "/bin/ps",
            arguments: ["-axo", "rss=,command="]
        )

        let totalKilobytes = output
            .split(separator: "\n")
            .compactMap { line -> Int64? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.isEmpty == false else { return nil }

                let parts = trimmed.split(omittingEmptySubsequences: true,
                                          whereSeparator: \.isWhitespace)
                guard parts.count >= 2, let kb = Int64(parts[0]) else { return nil }

                let executablePath = String(parts[1])
                let exe = executablePath.split(separator: "/").last.map(String.init) ?? executablePath
                let lower = exe.lowercased()
                guard lower == "ollama" || lower == "ollama-runner" else { return nil }

                return kb
            }
            .reduce(0, +)

        guard totalKilobytes > 0 else { return nil }
        return totalKilobytes * 1024
    }

    private static func rssForPID(_ pid: Int32) async -> Int64? {
        let output = await runProcess(
            executable: "/bin/ps",
            arguments: ["-o", "rss=", "-p", String(pid)]
        )
        let kilobytes = Int64(output.trimmingCharacters(in: .whitespacesAndNewlines))
        return kilobytes.map { $0 * 1024 }
    }

    private static func runProcess(executable: String, arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let timeoutItem = DispatchWorkItem {
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0, execute: timeoutItem)

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    timeoutItem.cancel()
                    continuation.resume(returning: "")
                    return
                }

                timeoutItem.cancel()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: stdout.isEmpty ? stderr : stdout)
            }
        }
    }
}
