# Repository Guidelines

## Project Structure & Module Organization
The active app lives in `OllamaBob/`, a Swift Package targeting macOS 14. Source is split by responsibility under `OllamaBob/OllamaBob/`: `Agent/` for the loop, approvals, and prompt budgeting; `Tools/` for structured local actions and shell execution; `Views/` for SwiftUI UI (including transcript chips and the rich HTML companion window); `Persistence/` for GRDB-backed storage; `Models/` for shared state/controllers (including `RichHTMLState`); `Services/` for app-level infrastructure that isn't a model-callable tool (e.g. `PromptComposerMemoryStore`, `AutomationProbe`, `PresentationService`); `Personality/` for prompt/persona logic; `Sound/` for audio playback; and `Resources/` for bundled assets. `ChatSessionController` owns transcript/session flow, while `ConversationStoreController` owns conversation list/search/pin/load/rename/delete behavior. Planning docs live in `docs/`, JSON contract samples in `samples/`, and design assets in `images/`. Treat `OllamaBob/.build/` and `OllamaBob/build/` as generated output.

## Build, Test, and Development Commands
Run commands from `OllamaBob/`.

- `swift build` builds the debug executable.
- `swift run OllamaBob` runs the app directly from SwiftPM.
- `./build.sh` assembles `build/OllamaBob.app`.
- `./build.sh --run` builds the app bundle and launches it.
- `swift test` runs the active XCTest suite for controllers, persistence, approval policy, and structured tools.

The app expects a local Ollama server at `http://localhost:11434`. `BRAVE_API_KEY` is optional and only affects web search.

Secrets live in a gitignored `.env` at the repo root. Use `.env.example` as the template when onboarding a new clone. `ELEVENLABS_API_KEY` + `OLLAMABOB_VOICE_ID` are only needed if you re-render the voice clips in `tools/render-bob-sayings.py`; the shipping app reads the pre-rendered audio from `Resources/Audio/`.

## Coding Style & Naming Conventions
Follow the existing Swift style: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods, and one primary type per file. Keep files focused and grouped by feature folder. Prefer clear Swift over clever abstractions, avoid force unwraps in production paths, and use `// MARK:` sections where they improve navigation. No formatter or linter is configured in this repo, so match surrounding code before introducing new patterns.

## Testing Guidelines
Use the active SwiftPM test target under `OllamaBob/Tests/OllamaBobTests/`. New logic-heavy work should add XCTest coverage alongside the feature. Name tests after behavior, for example `testPreflightFailsWhenOllamaIsUnavailable()`. Prioritize controller behavior, approval/path policy, persistence ordering, and structured tool edge cases. If a feature replaces a shell path with a first-class tool, add both approval tests and an execution-path test.

## Commit & Pull Request Guidelines
Recent history uses short Conventional Commit subjects such as `feat:` and `fix:`. Keep that format, write in the imperative, and scope each commit to one change. Pull requests should include a concise summary, user-visible impact, setup or migration notes, and screenshots or short recordings for UI changes to `Views/` or menu bar behavior. Link the relevant issue or planning doc when work follows `docs/` specifications.

## Security & Configuration Notes
Do not hardcode secrets. Read runtime keys from environment variables or user defaults, and keep sample payloads in `samples/` scrubbed of private data. Prefer first-class tools such as `read_file`, `list_directory`, `write_file`, `move_file`, `git_status`, and `git_diff` over broad `shell` calls when the task fits an existing structured action.
