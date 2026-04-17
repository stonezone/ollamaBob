#!/bin/bash
# Investigation C (partial) — can jq be bundled + codesigned for distribution?
#
# This test covers the BIG risk reviewers #1 and #2 flagged: "dylibbundler
# can't actually bundle Homebrew binaries because their dylib chains use
# hardcoded @loader_path / absolute prefixes."
#
# Steps:
#   1. Create a synthetic .app skeleton: InvC.app/Contents/{MacOS,Frameworks,Resources}
#   2. Copy /opt/homebrew/bin/jq into InvC.app/Contents/Resources/bin/jq
#   3. Run dylibbundler to rewrite jq's dylib load paths to @executable_path/../Frameworks
#      and copy the dylibs into Frameworks/
#   4. Verify the new jq's otool -L output has NO absolute /opt/homebrew paths
#   5. Codesign every Mach-O with the local Apple Development cert + hardened runtime
#   6. Execute the bundled jq via `InvC.app/Contents/Resources/bin/jq --version`
#      and via a short JSON pipeline, confirming it actually runs
#   7. Report pass/fail for each sub-step
#
# FULL notarization (xcrun notarytool submit) is DEFERRED — requires a
# Developer ID Application cert which is not in this keychain. This test
# covers the bundling + signing half, which is the actually hard part.

set -u
set -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$HERE/InvC.app"
APP_MACOS="$APP/Contents/MacOS"
APP_FW="$APP/Contents/Frameworks"
APP_RES="$APP/Contents/Resources"
APP_BIN="$APP_RES/bin"
BUNDLED_JQ="$APP_BIN/jq"
REPORT="$HERE/invC_report.txt"

CERT="Apple Development: zachariah jordan (4553ZWNVW7)"

# Clean any prior run
rm -rf "$APP"

# Step 1 — synthetic .app skeleton
echo "=== Investigation C: jq bundling smoke test ===" | tee "$REPORT"
echo "Started: $(date -u +%FT%TZ)" | tee -a "$REPORT"
echo | tee -a "$REPORT"

echo "[1] Creating .app skeleton at $APP" | tee -a "$REPORT"
mkdir -p "$APP_MACOS" "$APP_FW" "$APP_BIN"

# A tiny stub binary so codesign has a "main executable" to sign
cat > /tmp/invC_main.c <<'EOF'
int main(void) { return 0; }
EOF
clang -o "$APP_MACOS/InvC" /tmp/invC_main.c
rm -f /tmp/invC_main.c

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>InvC</string>
  <key>CFBundleIdentifier</key><string>com.stonezone.ollamabob.invc</string>
  <key>CFBundleName</key><string>InvC</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Step 2 — copy jq
echo "[2] Copying jq 1.8.1 from Homebrew into Resources/bin/" | tee -a "$REPORT"
cp "$(readlink -f /opt/homebrew/bin/jq)" "$BUNDLED_JQ"
chmod +x "$BUNDLED_JQ"

echo "    BEFORE otool -L:" | tee -a "$REPORT"
otool -L "$BUNDLED_JQ" | sed 's/^/      /' | tee -a "$REPORT"

# Step 3 — dylibbundler
echo "[3] Running dylibbundler…" | tee -a "$REPORT"
# dylibbundler flags:
#   -cd  create destination dir if missing
#   -of  overwrite existing dylibs in dest
#   -b   bundle ALL non-system libs (anything not in /usr/lib or /System)
#   -x   the binary to fix
#   -d   where dylibs should be copied
#   -p   what @rpath to rewrite references to (relative to the binary)
set +e
dylibbundler -cd -of -b \
  -x "$BUNDLED_JQ" \
  -d "$APP_FW/" \
  -p "@executable_path/../../Frameworks/" \
  2>&1 | sed 's/^/    /' | tee -a "$REPORT"
DBB_EXIT=${PIPESTATUS[0]}
set -e
echo "    dylibbundler exit: $DBB_EXIT" | tee -a "$REPORT"

# Step 4 — verify no absolute /opt/homebrew paths remain
echo "[4] AFTER otool -L on bundled jq:" | tee -a "$REPORT"
otool -L "$BUNDLED_JQ" | sed 's/^/      /' | tee -a "$REPORT"

if otool -L "$BUNDLED_JQ" | grep -q "/opt/homebrew"; then
  echo "    ❌ FAIL: /opt/homebrew path still present in bundled jq" | tee -a "$REPORT"
  BUNDLE_OK=0
else
  echo "    ✅ No /opt/homebrew absolute paths in bundled jq" | tee -a "$REPORT"
  BUNDLE_OK=1
fi

# Verify dylibs in Frameworks/ also have no /opt/homebrew refs
echo "    Frameworks/ contents:" | tee -a "$REPORT"
ls -la "$APP_FW" 2>/dev/null | sed 's/^/      /' | tee -a "$REPORT"
for dylib in "$APP_FW"/*.dylib; do
  [ -e "$dylib" ] || continue
  echo "    otool -L $(basename "$dylib"):" | tee -a "$REPORT"
  otool -L "$dylib" | sed 's/^/      /' | tee -a "$REPORT"
  if otool -L "$dylib" | grep -q "/opt/homebrew"; then
    echo "    ❌ FAIL: $(basename "$dylib") still references /opt/homebrew" | tee -a "$REPORT"
    BUNDLE_OK=0
  fi
done

# Step 5 — codesign every Mach-O with hardened runtime
echo "[5] Codesigning with '$CERT'…" | tee -a "$REPORT"
SIGN_OK=1

# Dylibs first, then the binary, then the app bundle (inside-out signing)
for dylib in "$APP_FW"/*.dylib; do
  [ -e "$dylib" ] || continue
  echo "    sign $(basename "$dylib")" | tee -a "$REPORT"
  if ! codesign --force --sign "$CERT" --timestamp --options runtime "$dylib" 2>&1 | tee -a "$REPORT"; then
    SIGN_OK=0
  fi
done

echo "    sign bundled jq" | tee -a "$REPORT"
if ! codesign --force --sign "$CERT" --timestamp --options runtime "$BUNDLED_JQ" 2>&1 | tee -a "$REPORT"; then
  SIGN_OK=0
fi

echo "    sign stub InvC binary" | tee -a "$REPORT"
if ! codesign --force --sign "$CERT" --timestamp --options runtime "$APP_MACOS/InvC" 2>&1 | tee -a "$REPORT"; then
  SIGN_OK=0
fi

echo "    sign whole .app" | tee -a "$REPORT"
if ! codesign --force --sign "$CERT" --timestamp --options runtime "$APP" 2>&1 | tee -a "$REPORT"; then
  SIGN_OK=0
fi

echo "    verify signature" | tee -a "$REPORT"
if codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/      /' | tee -a "$REPORT"; then
  echo "    ✅ codesign verify passed" | tee -a "$REPORT"
else
  echo "    ❌ codesign verify failed" | tee -a "$REPORT"
  SIGN_OK=0
fi

# Step 6 — actually run bundled jq
echo "[6] Running bundled jq --version" | tee -a "$REPORT"
RUN_OK=1
if VERSION_OUT=$("$BUNDLED_JQ" --version 2>&1); then
  echo "    version: $VERSION_OUT" | tee -a "$REPORT"
else
  echo "    ❌ --version failed: $VERSION_OUT" | tee -a "$REPORT"
  RUN_OK=0
fi

echo "    running a real jq filter" | tee -a "$REPORT"
JSON_IN='{"models":[{"name":"gemma4:e4b","size":9163},{"name":"qwen3:14b","size":8846}]}'
if FILTER_OUT=$(echo "$JSON_IN" | "$BUNDLED_JQ" -r '.models[].name' 2>&1); then
  echo "    filter result:" | tee -a "$REPORT"
  echo "$FILTER_OUT" | sed 's/^/      /' | tee -a "$REPORT"
  if [ "$(echo "$FILTER_OUT" | tr '\n' ' ' | xargs)" != "gemma4:e4b qwen3:14b" ]; then
    echo "    ❌ filter output unexpected" | tee -a "$REPORT"
    RUN_OK=0
  fi
else
  echo "    ❌ filter failed: $FILTER_OUT" | tee -a "$REPORT"
  RUN_OK=0
fi

# Step 7 — summary
echo | tee -a "$REPORT"
echo "=== RESULTS ===" | tee -a "$REPORT"
echo "bundle_ok = $BUNDLE_OK    (all dylib refs rewritten)" | tee -a "$REPORT"
echo "sign_ok   = $SIGN_OK      (hardened-runtime codesign + verify)" | tee -a "$REPORT"
echo "run_ok    = $RUN_OK       (bundled jq actually executes)" | tee -a "$REPORT"

if [ "$BUNDLE_OK" = "1" ] && [ "$SIGN_OK" = "1" ] && [ "$RUN_OK" = "1" ]; then
  echo "VERDICT: PARTIAL PASS — jq can be bundled, signed, and executed locally." | tee -a "$REPORT"
  echo "         Full notarization gate still deferred (needs Developer ID Application cert)." | tee -a "$REPORT"
  exit 0
else
  echo "VERDICT: FAIL" | tee -a "$REPORT"
  exit 1
fi
