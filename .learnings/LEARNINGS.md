# Learnings Log

Running log of corrections, knowledge gaps, and best practices discovered while working on OllamaBob. See `.claude/skills/self-improving-agent` for schema.

---

## [LRN-20260417-001] knowledge_gap

**Logged**: 2026-04-17T07:40:39Z
**Priority**: medium
**Status**: pending
**Area**: infra

### Summary
SPM `.process(...)` flattens resource subdirectories into the bundle root — lookups with a `subdirectory:` parameter fail at runtime.

### Details
Added 50 MP3 clips under `OllamaBob/OllamaBob/Resources/BobSayings/` and declared the whole `Resources/` dir via `.process("Resources")` in `Package.swift`. Expected to read them with:

```swift
Bundle.main.url(forResource: name, withExtension: "mp3", subdirectory: "BobSayings")
```

This returned `nil` at runtime. Inspecting `build/OllamaBob.app/Contents/Resources/OllamaBob_OllamaBob.bundle/` showed all 50 files flattened to the bundle root — no `BobSayings/` subdir. This is `.process()` behavior; to preserve structure, use `.copy("Resources/BobSayings")` instead.

Also, because resources are owned by an SPM target (not the executable shell), the correct bundle to query is `Bundle.module`, not `Bundle.main`. `Bundle.main` does work once `build.sh` copies the SPM resource bundle into `Contents/Resources`, but `Bundle.module` is the idiomatic accessor.

### Suggested Action
- If resources must retain directory hierarchy (e.g., localization, per-persona assets), switch `.process(...)` → `.copy(...)` in `Package.swift`.
- For flat resource pools, keep `.process()` and drop the `subdirectory:` argument; filenames must be globally unique (our content-addressed `category-<hash>.mp3` naming already satisfies this).
- Prefer `Bundle.module` for accessing target-owned resources.

### Metadata
- Source: error
- Related Files: OllamaBob/OllamaBob/Sound/BobSayings.swift, OllamaBob/Package.swift, OllamaBob/build.sh
- Tags: spm, resources, bundle, swift

---

## [LRN-20260417-002] best_practice

**Logged**: 2026-04-17T07:40:39Z
**Priority**: medium
**Status**: pending
**Area**: infra

### Summary
Pre-rendering TTS clips at build time is a cheap, tokenless way to add voice personality to a local-first app — as long as triggers are sparse and gated per persona.

### Details
Bob's V2.5 voice pass rendered 50 ElevenLabs MP3s (~$0.50 one-time) bundled into Resources/, rather than streaming live TTS on each message. Trade-offs that worked out:

- **Zero runtime API dependency** — app still works offline, still fast.
- **Deterministic costs** — re-render only runs when the JSON catalog changes, and the Python script skips existing files by content hash.
- **Persona gating is essential** — playing Mumbai-accented lines while the user is on Terse Engineer or Grumpy Linus would break character. `BobSayings.play` short-circuits if `PersonaStore.shared.activePersonaID != BuiltinPersonas.mumbaiBobID`.
- **Two-toggle split** — users want "Tink on send" (unobtrusive) separate from "Bob speaks sentences" (much more obtrusive). Kept as independent `soundsEnabled` + `bobVoiceEnabled` settings.

### Suggested Action
If adding voice lines to new personas: render each persona's catalog under its own voice ID, namespace files by persona in the manifest, and key playback on `activePersonaID` rather than a global toggle.

### Metadata
- Source: conversation
- Related Files: tools/render-bob-sayings.py, tools/bob-sayings.json, OllamaBob/OllamaBob/Sound/BobSayings.swift
- Tags: tts, elevenlabs, personas, cost-management

---
