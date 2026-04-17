# Errors Log

Running log of failures encountered while working on OllamaBob. See `.claude/skills/self-improving-agent` for schema.

---

## [ERR-20260417-001] app_launch

**Logged**: 2026-04-17T07:40:39Z
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
`open OllamaBob.app` fails with launchd error 162 after rebuild when a new framework (e.g. AVFoundation) is imported.

### Error
```
The application cannot be opened for an unexpected reason, error=Error
Domain=RBSRequestErrorDomain Code=5 "Launch failed."
UserInfo={NSLocalizedFailureReason=Launch failed.,
NSUnderlyingError=...Error Domain=NSPOSIXErrorDomain Code=162
"Unknown error: 162" UserInfo={NSLocalizedDescription=Launchd job spawn failed}}
```

Running the binary directly (`/path/to/OllamaBob.app/Contents/MacOS/OllamaBob`) exits silently with no stderr output.

### Context
- Triggered after adding `import AVFoundation` to a new Swift file (BobSayings.swift).
- `swift build` succeeded and the `.app` bundle was assembled correctly (MP3s bundled, Info.plist present).
- `xattr -cr` on the bundle did not fix it.
- `lsregister -f` on the bundle did not fix it alone.

### Suggested Fix
Re-apply an ad-hoc code signature after every rebuild that adds a framework import or changes entitlements:

```bash
codesign --force --deep --sign - /path/to/OllamaBob.app
```

Consider adding this step to `build.sh` so the problem doesn't recur. The cost is negligible (<100ms) and it makes builds immediately launchable.

### Metadata
- Reproducible: yes — any time a new framework is first imported
- Related Files: OllamaBob/build.sh, OllamaBob/OllamaBob/Sound/BobSayings.swift

### Resolution
- **Resolved**: 2026-04-17T07:38:00Z
- **Commit**: build.sh auto-signs every build (no manual step needed)
- **Notes**: Ran `codesign --force --deep --sign -` against the bundle; subsequent `open` launched cleanly (PID 86684). Then folded the same line into `build.sh` so future rebuilds launch without manual intervention.

---
