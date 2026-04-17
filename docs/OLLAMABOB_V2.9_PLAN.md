# OllamaBob V2.9 — Phase A: Native Tool Expansion

**Handoff plan for an autonomous coding agent (Codex CLI).**
This document is the single source of truth for V2.9 Phase A. Do not deviate from it. If any instruction here conflicts with `CLAUDE.md` or `AGENTS.md`, this plan wins **for the scope of this work only**. Do not modify `CLAUDE.md` or `AGENTS.md` except in the specific section called out below.

Working directory for all commands: `/Users/zack/ollamaBob/OllamaBob/`

---

## 1. Mission

Add seven new first-class tools to OllamaBob so he can OCR images, speak, fetch weather, convert units, resize/convert images with `sips`, and search + download media with `yt-dlp`. Each tool follows the existing structured-tool pattern in `Tools/`. Ship as one bundled commit tagged `v2.9`, using the same build-and-launch gate that shipped V2.6, V2.7, and V2.8.

---

## 2. Non-Negotiable Guardrails (Strict No-Drift Rules)

Read these before writing a line of code. If you find yourself wanting to do something not on this list, **stop and re-read the plan** — the answer is almost certainly "don't."

### What you MUST NOT do

1. **Do not modify any existing tool file.** `ClipboardTool.swift`, `AppleScriptTool.swift`, `ShellTool.swift`, `FileReadTool.swift`, `FileWriteTool.swift`, `FileMoveTool.swift`, `FileSearchTool.swift`, `DirectoryCreateTool.swift`, `DirectoryListTool.swift`, `GitStatusTool.swift`, `GitDiffTool.swift`, `GitToolRunner.swift`, `WebSearchTool.swift`, `SearchProvider.swift`, `ToolOutputStore.swift`, `ToolRuntime.swift`, `ToolCatalog.swift` — all OFF LIMITS for edits.
2. **Do not refactor anything.** Not adjacent code, not helper extraction, not import re-ordering, not renaming, not "while I'm here." Zero drive-by changes.
3. **Do not change `Package.swift`.** No new SPM dependencies. Every framework needed (`Foundation`, `AppKit`, `Vision`, `CoreImage`) is already available in Apple's SDK — just `import` it.
4. **Do not add new approval levels.** Only `.none`, `.modal`, and `.forbidden` exist. Use them as specified below.
5. **Do not add nested tool parameter schemas.** Every property is a single-level string, integer, or boolean — never an object or array. This is a hard rule in `CLAUDE.md` and it exists because Gemma 4 chokes on nested schemas.
6. **Do not add tools beyond the seven listed.** No "while I'm here, I also added…"
7. **Do not modify `Info.plist` or entitlements.** None of Phase A needs them.
8. **Do not touch the UI layer (`Views/`) except `PreferencesView.swift`.** And only for the one change specified below.
9. **Do not add logging frameworks or metrics.** Use the existing `logTool()` call pattern that the existing tools already feed.
10. **Do not add retry loops or fallback behavior.** If a shell tool binary is missing, return a clear `.failure` and let the user `brew install` it. Do not invoke Homebrew on the user's behalf.
11. **Do not change the commit message template at the bottom of this document** — use it as-is, only fill in the placeholders.
12. **Do not push.** Commit locally only. The user pushes.

### What you MUST do

1. **Build after every single file you create or edit.** Do not stack edits and build once at the end. The command is `swift build` from `/Users/zack/ollamaBob/OllamaBob/`. Fix any error before moving on.
2. **Run the full test suite at every checkpoint.** `swift test` from the same directory. All tests must pass before you move to the next checkpoint.
3. **Launch the app at the end.** `./build.sh --run` from `/Users/zack/ollamaBob/OllamaBob/`. The app must launch without a preflight error. You cannot visually verify Bob's responses (no user in the loop), but you can verify the build succeeded and the app starts.
4. **Write tests for every tool** using the patterns already established in `Tests/OllamaBobTests/StructuredFileToolTests.swift` and `Tests/OllamaBobTests/PolicyRegressionTests.swift`.
5. **Follow the existing Swift style.** Four-space indent, `UpperCamelCase` types, `lowerCamelCase` methods, `enum <ToolName>` namespace with `static func execute(...)`, same short doc-comment style as `ClipboardTool.swift`.
6. **Keep files small.** Target under 150 lines each. If a tool's implementation exceeds that, it's probably doing too much — split the work inside the tool, not across files, unless you have an obvious reason.

### Stop conditions

Stop immediately and surface the blocker if:

- `swift build` fails after an edit and the fix isn't obviously in the file you just wrote. Do not start editing other files to "help it compile."
- A test in `Tests/OllamaBobTests/` that was passing before your changes starts failing. Something is wrong with your new code — do not "update" the existing test.
- You feel the urge to modify a file not listed in Section 5. Stop and re-read Section 2.
- You hit an Apple API you're unsure about (e.g., Vision framework behavior on older macOS). Do not guess. Write a minimal check, build, verify, then proceed.

---

## 3. The Seven Tools

All seven follow the same shape as the existing tools. Each lives in its own file under `OllamaBob/OllamaBob/Tools/` with the pattern:

```swift
import Foundation
// additional imports as needed

enum NewTool {
    private static let maxOutputChars = 10_000

    static func execute(...) async -> ToolResult {
        let start = Date()
        // validation
        // work
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)
        return .success(tool: "new_tool", content: "...", durationMs: durationMs)
        // or .failure(tool: "new_tool", error: "...", durationMs: durationMs)
    }
}
```

The exact schema, approval level, and behavior for each tool:

### 3.1 `ocr`

- **File:** `Tools/OCRTool.swift`
- **Imports:** `Foundation`, `AppKit`, `Vision`, `CoreImage`
- **Schema:**
  - `path` — `string`, optional. Absolute path to a local image file. If omitted, read the current clipboard image instead.
- **Required args:** none.
- **Approval:** `.none`.
- **Behavior:**
  - If `path` is empty or missing, pull image from `NSPasteboard.general`. Accept `.png`, `.tiff`, `.pdf` — try `.png` first, then `.tiff`. If neither is present, return `.failure` with `"Clipboard does not contain an image."`.
  - If `path` is given, load via `NSImage(contentsOfFile:)` then convert to `CGImage`. If that fails, return `.failure` with `"Could not load image at <path>."`.
  - Run `VNRecognizeTextRequest` with `recognitionLevel = .accurate` and `usesLanguageCorrection = true`.
  - Join observed lines with `\n`. If zero observations, return `.success` with content `"(no text found in image)"`.
  - Truncate output to 10,000 chars with the standard truncation note used elsewhere (`"... [TRUNCATED: X total chars, showing first 10000] ..."`).
- **Tool description for ToolRegistry:**
  > "Extract text from an image using Apple's Vision framework. If `path` is provided, OCR that file. If omitted, OCR the current clipboard image (works with screenshots). Returns the recognized text."

### 3.2 `speak`

- **File:** `Tools/SayTool.swift`
- **Imports:** `Foundation`
- **Schema:**
  - `text` — `string`, required. What to say.
  - `voice` — `string`, optional. macOS voice name (e.g. "Samantha", "Daniel"). Defaults to system voice if omitted.
- **Required args:** `["text"]`.
- **Approval:** `.none`.
- **Behavior:**
  - Cap text at 2,000 chars. If longer, return `.failure` with `"Text too long: \(count) chars (max 2000)."`.
  - If text is empty after trim, return `.failure` with `"Text is empty."`.
  - Spawn `/usr/bin/say` via `Process` (match the pattern in `ShellTool.swift`). Args: `["-v", voice, text]` if voice is provided, else `[text]`.
  - Do not wait for playback to complete — `say` returns fast once playback starts.
  - On success return `.success` with content `"Spoke \(count) chars."`.
- **Tool description:**
  > "Speak the given text aloud using macOS built-in text-to-speech. Optional `voice` parameter picks a named macOS voice (e.g. 'Samantha'). Returns immediately once playback starts."

### 3.3 `weather`

- **File:** `Tools/WeatherTool.swift`
- **Imports:** `Foundation`
- **Schema:**
  - `location` — `string`, required. A city, airport code, postal code, or lat,lon pair.
- **Required args:** `["location"]`.
- **Approval:** `.none`.
- **Behavior:**
  - URL-encode the location.
  - `URLSession.shared.data(from: URL("https://wttr.in/<encoded>?format=3"))`.
  - 10-second timeout via `URLSessionConfiguration.default` and `timeoutIntervalForRequest = 10`.
  - On network failure or non-200 response, return `.failure` with the error message.
  - Return the response body stripped of trailing whitespace.
- **Tool description:**
  > "Get the current weather for a location. Pass a city ('Honolulu'), airport code ('HNL'), postal code, or 'lat,lon'. Returns a one-line summary."

### 3.4 `unit_convert`

- **File:** `Tools/UnitsTool.swift`
- **Imports:** `Foundation`
- **Schema:**
  - `from` — `string`, required. Value with unit, e.g. `"5 miles"`, `"100 C"`, `"1 gbp"`.
  - `to` — `string`, required. Target unit, e.g. `"kilometers"`, `"F"`, `"usd"`.
- **Required args:** `["from", "to"]`.
- **Approval:** `.none`.
- **Behavior:**
  - Spawn `/usr/bin/units -t <from> <to>` via `Process`.
  - 5-second timeout (use `DispatchQueue.global().asyncAfter` + `process.terminate()` pattern or the existing timeout pattern in `ShellTool.swift`).
  - Capture stdout. If empty or contains `"conformability error"`, return `.failure` with the stderr or a fallback message like `"Cannot convert <from> to <to>."`.
  - On success, return trimmed stdout (typically a single number). Prepend with the human form: `"\(from) = \(result) \(to)"`.
- **Tool description:**
  > "Convert between units using the macOS `units` tool. Works for length, mass, temperature, volume, currency (with stale rates), and many more. Pass `from` as a value+unit ('5 miles') and `to` as a unit name ('kilometers')."

### 3.5 `image_convert`

- **File:** `Tools/SipsTool.swift`
- **Imports:** `Foundation`
- **Schema:**
  - `input_path` — `string`, required. Absolute source image path.
  - `output_path` — `string`, required. Absolute destination image path.
  - `format` — `string`, required. One of `"jpeg"`, `"png"`, `"tiff"`, `"heic"`, `"gif"`, `"bmp"`.
  - `max_dimension` — `integer`, optional. If provided, proportionally resize so neither side exceeds this value.
- **Required args:** `["input_path", "output_path", "format"]`.
- **Approval:** `.modal` (writes a file).
- **Behavior:**
  - Validate `format` is one of the allowed strings; otherwise `.failure`.
  - Validate `max_dimension` (if provided) is between 16 and 16384; otherwise `.failure`.
  - Spawn `/usr/bin/sips` with args: `["-s", "format", format]` + (if `max_dimension`: `["-Z", String(max_dimension)]`) + `[input_path, "--out", output_path]`.
  - 30-second timeout.
  - Parse stdout. `sips` prints the input path on success. If stderr contains `"Error:"` or `process.terminationStatus != 0`, return `.failure` with the stderr.
  - On success return `.success` with content `"Wrote \(output_path) (\(format)\(max_dimension != nil ? ", max \(max_dimension)px" : "")"`.
- **Tool description:**
  > "Convert or resize an image using the native macOS `sips` tool. `format` is jpeg/png/tiff/heic/gif/bmp. Optional `max_dimension` proportionally shrinks so neither side exceeds that many pixels. Requires approval (writes a file)."

### 3.6 `youtube_search`

- **File:** `Tools/YouTubeTool.swift` (shared with `youtube_download`)
- **Imports:** `Foundation`
- **Schema:**
  - `query` — `string`, required. Free-text search, e.g. `"Taylor Swift Anti-Hero"`.
  - `limit` — `integer`, optional. Number of results, default 5, clamp 1–10.
- **Required args:** `["query"]`.
- **Approval:** `.none` (read-only probe).
- **Behavior:**
  - Resolve `yt-dlp` via `which yt-dlp` (Process). If missing, return `.failure` with `"yt-dlp not found on PATH. Install with: brew install yt-dlp"`.
  - Spawn: `yt-dlp --dump-json --no-warnings "ytsearch\(limit):<query>"`. Parse stdout as NDJSON (one JSON object per line).
  - For each entry, extract `title`, `uploader`, `duration` (seconds — convert to `mm:ss`), `webpage_url`.
  - Return a formatted table, one result per line:
    ```
    1. [4:32] Taylor Swift - Anti-Hero (Official Video) — Taylor Swift
       https://www.youtube.com/watch?v=...
    2. ...
    ```
  - 30-second timeout. Truncate to 5,000 chars.
- **Tool description:**
  > "Search YouTube and return up to 10 candidate videos with title, uploader, duration, and URL. Use this before `youtube_download` to let the user pick the right result. Requires yt-dlp to be installed (brew install yt-dlp)."

### 3.7 `youtube_download`

- **File:** `Tools/YouTubeTool.swift` (same file as `youtube_search`)
- **Imports:** `Foundation`
- **Schema:**
  - `url` — `string`, required. A full YouTube URL.
  - `format` — `string`, required. One of `"mp3"`, `"m4a"`, `"mp4"`, `"bestaudio"`, `"bestvideo"`.
  - `output_dir` — `string`, optional. Absolute directory path. Default `~/Music/Bob/` if `format` is audio, else `~/Downloads/Bob/`.
- **Required args:** `["url", "format"]`.
- **Approval:** `.modal` (writes a file, uses the network).
- **Behavior:**
  - Validate `url` starts with `http://` or `https://`, and contains `youtu` (youtube.com or youtu.be).
  - Validate `format` is in the allowed list.
  - Resolve `yt-dlp` via `which yt-dlp`; if missing, `.failure` as above.
  - Default `output_dir`: audio formats (`mp3`, `m4a`, `bestaudio`) → `~/Music/Bob/`; video formats → `~/Downloads/Bob/`.
  - Expand `~` to `NSHomeDirectory()`. `mkdir -p` the output dir if missing.
  - Build args:
    - For `mp3`: `["-x", "--audio-format", "mp3", "-o", "<output_dir>/%(title)s.%(ext)s", url]`
    - For `m4a`: `["-x", "--audio-format", "m4a", "-o", "<output_dir>/%(title)s.%(ext)s", url]`
    - For `bestaudio`: `["-f", "bestaudio", "-o", "<output_dir>/%(title)s.%(ext)s", url]`
    - For `mp4`: `["-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4", "-o", "<output_dir>/%(title)s.%(ext)s", url]`
    - For `bestvideo`: `["-f", "bestvideo", "-o", "<output_dir>/%(title)s.%(ext)s", url]`
  - 300-second timeout (downloads can be slow; `yt-dlp` already streams progress to stderr).
  - Parse the `[download] Destination: <path>` line from stderr to extract the saved file path. Final `[ExtractAudio] Destination:` takes precedence.
  - On success return `.success` with content `"Downloaded to <saved_path>"`.
- **Tool description:**
  > "Download audio or video from a YouTube URL using yt-dlp. `format` is mp3/m4a/mp4/bestaudio/bestvideo. Default output dirs: ~/Music/Bob/ for audio, ~/Downloads/Bob/ for video. Requires approval."

---

## 4. Path Policy Touch-Ups

None required. Default output dirs (`~/Music/Bob/`, `~/Downloads/Bob/`) both fall under the home directory and are already `.allowed` per `PathPolicy.check()`.

Do **not** add new entries to `PathPolicy.swift`.

---

## 5. File-By-File Change List

Exhaustive list. If a file isn't here, don't touch it.

### New files (create)

1. `OllamaBob/OllamaBob/Tools/OCRTool.swift`
2. `OllamaBob/OllamaBob/Tools/SayTool.swift`
3. `OllamaBob/OllamaBob/Tools/WeatherTool.swift`
4. `OllamaBob/OllamaBob/Tools/UnitsTool.swift`
5. `OllamaBob/OllamaBob/Tools/SipsTool.swift`
6. `OllamaBob/OllamaBob/Tools/YouTubeTool.swift`
7. `OllamaBob/Tests/OllamaBobTests/Phase2_9ToolTests.swift`

### Files to edit (only these, only the specified section)

1. **`OllamaBob/OllamaBob/Agent/ToolRegistry.swift`** — add seven tool definitions at the bottom of `init(braveKeyAvailable:)`, right before `self.tools = defs`. Match the format of the existing `applescript` and `clipboard_write` entries.

2. **`OllamaBob/OllamaBob/Agent/ApprovalPolicy.swift`** — add seven new `case` arms inside the `switch toolName { ... }` block in `check(toolName:arguments:)`, placed just before `case "shell":`. Approvals per Section 3. For `image_convert` and `youtube_download` (both `.modal`), use a literal `return .modal` — do not thread them through `structuredWriteApproval`. Their output paths are user-provided and the modal dialog shows the full command the user is approving.

3. **`OllamaBob/OllamaBob/Agent/AgentLoop.swift`** — two edits, nothing else:
   - In the `executeTool(name:args:)` switch (around line 240–320), add seven new `case` arms **before** the `default:` line. Follow the exact pattern of existing arms. Parse args conservatively (use `Self.parseInt` helper that already exists for integers).
   - In the `describeToolCall(name:args:)` switch (around line 568–621), add seven human-readable labels for the Activity log. Examples:
     - `case "ocr": return args["path"].map { "OCR file: \($0)" } ?? "OCR clipboard image"`
     - `case "speak": return "Speak: \(String((args["text"] as? String ?? "").prefix(60)))"`
     - `case "weather": return "Weather: \(args["location"] as? String ?? "?")"`
     - `case "unit_convert": return "Convert \(args["from"] as? String ?? "?") → \(args["to"] as? String ?? "?")"`
     - `case "image_convert": return "Convert image: \(args["input_path"] as? String ?? "?") → \(args["output_path"] as? String ?? "?")"`
     - `case "youtube_search": return "YouTube search: \(args["query"] as? String ?? "?")"`
     - `case "youtube_download": return "YouTube download: \(args["url"] as? String ?? "?")"`

4. **`OllamaBob/OllamaBob/Views/PreferencesView.swift`** — *only if* the Tools tab renders from `ToolCatalog.json`, add no changes (the Tools tab is driven by ToolRuntime probing the bundled catalog; the new first-class tools are *not* external binaries and don't belong there). **Skip this file entirely for Phase A.** It is listed here only so you verify by reading that you shouldn't touch it.

### Files to explicitly leave alone

- `Tools/ToolCatalog.swift` and `Resources/ToolCatalog.json` — these are for the `tool_help` meta-tool that lists *external CLI binaries*. The new seven are first-class structured tools and do not belong in this catalog.
- `Tools/ToolRuntime.swift` — runtime probes for external CLI binaries (versions, whether they're on PATH). None of the Phase A tools need a probe: OCR/speak/weather/units/sips are always available on macOS; yt-dlp is probed at call time inside `YouTubeTool.swift`.
- Any file under `Views/`, `Models/`, `Personality/`, `Persistence/`, `Resources/`.

---

## 6. Build Order & Checkpoints

Do these in order. Each checkpoint ends with `swift build && swift test`. Do not proceed past a failing checkpoint.

### Checkpoint 1 — OCR

1. Create `OCRTool.swift`.
2. Add `ocr` to `ToolRegistry.swift`.
3. Add `ocr` case to `ApprovalPolicy.swift`.
4. Add `ocr` case to both switches in `AgentLoop.swift`.
5. Write tests for approval classification and a basic "OCR an image with known text" test. For the test, construct a `CIImage` from a programmatically-drawn `NSImage` containing the text "HELLO BOB", save to a temp PNG, OCR it, assert the result contains "HELLO" and "BOB".
6. `swift build && swift test`. Must pass.

### Checkpoint 2 — say / weather / units

1. Create `SayTool.swift`, `WeatherTool.swift`, `UnitsTool.swift`.
2. Add three entries to `ToolRegistry.swift`.
3. Add three cases to `ApprovalPolicy.swift` (all `.none`).
4. Add three cases to both switches in `AgentLoop.swift`.
5. Tests:
   - Approval classification for all three.
   - `speak`: call with `text: "test"`, assert success and that duration is under 2 seconds (don't wait for playback).
   - `weather`: mock not required — this is a live network test. Skip the live call; test only the URL construction and error path when location is empty.
   - `unit_convert`: call with `from: "5 miles", to: "kilometers"`, assert the result contains a number between 8.0 and 8.1.
6. `swift build && swift test`. Must pass.

### Checkpoint 3 — image_convert

1. Create `SipsTool.swift`.
2. Register in `ToolRegistry.swift`, `ApprovalPolicy.swift` (`.modal`), `AgentLoop.swift`.
3. Tests:
   - Approval classification: any input returns `.modal`.
   - Invalid format returns `.failure`.
   - Roundtrip: write a 2×2 PNG to a temp file, convert to JPEG at a temp output path, assert output file exists and is >0 bytes.
4. `swift build && swift test`. Must pass.

### Checkpoint 4 — youtube_search / youtube_download

1. Create `YouTubeTool.swift` with both functions.
2. Register both in `ToolRegistry.swift`, `ApprovalPolicy.swift` (search = `.none`, download = `.modal`), `AgentLoop.swift`.
3. Tests:
   - Approval classification for both.
   - URL validation on download: reject empty URL, reject non-YouTube URL, reject missing format.
   - Invalid format rejected.
   - yt-dlp-missing path: if `which yt-dlp` returns non-zero, the tool returns `.failure` with a clear install hint. To test this, temporarily override `PATH=""` via `ProcessInfo` — or skip this test if it can't be done cleanly without reaching into global state. Don't gold-plate.
   - Do **not** test actual YouTube downloads in the test suite.
4. `swift build && swift test`. Must pass.

### Checkpoint 5 — Build gate

1. `./build.sh` from `/Users/zack/ollamaBob/OllamaBob/`. Must produce `build/OllamaBob.app`.
2. `./build.sh --run`. App must launch without a preflight error dialog.
3. If launch fails, stop and surface the error. Do not attempt to patch unrelated code to make the app launch.

---

## 7. Test Organization

Put all seven tools' tests in **one** new file to keep the check cheap: `Tests/OllamaBobTests/Phase2_9ToolTests.swift`.

Structure:

```swift
import XCTest
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
        XCTAssertEqual(
            ApprovalPolicy.check(toolName: "youtube_search", arguments: ["query": "foo"]),
            .none
        )
        XCTAssertEqual(
            ApprovalPolicy.check(
                toolName: "youtube_download",
                arguments: ["url": "https://youtube.com/watch?v=x", "format": "mp3"]
            ),
            .modal
        )
    }

    // MARK: - Execution (one per tool)

    // ...add one focused test per tool per Section 6 checkpoints...
}
```

Name each execution test `test<ToolName><Behavior>`, e.g. `testOCRExtractsTextFromGeneratedImage`, `testSipsConvertsPNGToJPEG`, `testUnitConvertMilesToKilometers`, `testYouTubeDownloadRejectsNonYouTubeURL`.

---

## 8. Acceptance Gates (final checks before commit)

Run these in order. All must pass.

1. **Compile:** `cd /Users/zack/ollamaBob/OllamaBob && swift build` — zero errors, zero new warnings.
2. **Tests:** `cd /Users/zack/ollamaBob/OllamaBob && swift test` — all tests pass, including the new `Phase2_9ToolTests` file.
3. **App bundle:** `cd /Users/zack/ollamaBob/OllamaBob && ./build.sh` — produces `build/OllamaBob.app`.
4. **Launch:** `cd /Users/zack/ollamaBob/OllamaBob && ./build.sh --run` — app launches without preflight error.
5. **Tool count check:** Confirm Bob now exposes seven new tools. From Swift REPL or via a quick print statement you add temporarily to `AgentLoop.init` (remove before commit), or just by counting entries in `ToolRegistry.swift` — the new count should be 23 (old) + 7 (new) = 30 tools registered (or 29 if Brave key isn't set).
6. **No unrelated diffs:** `git diff --stat` — the only changed files should be those listed in Section 5. If anything else shows up, revert it.

---

## 9. Commit

One commit for all of Phase A. Use this exact message template — fill in nothing, just use as-is:

```
feat: V2.9 — Phase A native tool expansion (OCR, say, weather, units, sips, yt-dlp)

Adds seven first-class tools to Bob's registry:

- ocr — Apple Vision text extraction from image paths or clipboard screenshots
- speak — native `say` TTS
- weather — wttr.in one-liner lookup
- unit_convert — native `units` conversion
- image_convert — `sips` convert/resize, modal-gated
- youtube_search — yt-dlp search returning candidate videos
- youtube_download — yt-dlp audio/video download, modal-gated

All follow the existing structured-tool pattern. Approval policy:
read-only tools (ocr, speak, weather, unit_convert, youtube_search)
are unapproved; file/network-write tools (image_convert,
youtube_download) require modal approval. Flat schemas throughout.

Tests cover approval classification and execution paths for all
seven tools in Phase2_9ToolTests.
```

Then: `git add -A && git commit -m "..."` (using the HEREDOC pattern from `CLAUDE.md`'s "Committing changes with git" section).

**Do not push.** User pushes manually.

---

## 10. When You're Done

Report back with:

1. The commit SHA.
2. `git diff --stat HEAD~1` output.
3. `swift test 2>&1 | tail -5` output.
4. Any deviations from this plan, with a one-line reason each.
5. Any known limitations of your implementation the user should test manually.

**Do not** report work you didn't actually finish. If you hit a blocker, stop and surface it — do not leave half-implemented code in the tree.
