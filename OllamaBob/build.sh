#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_BUNDLE="build/OllamaBob.app"
CONTENTS="$APP_BUNDLE/Contents"

# Kill existing instance
pkill -f "OllamaBob.app" 2>/dev/null || true
sleep 1

echo "Building OllamaBob..."
swift build -c debug 2>&1

echo "Assembling app bundle..."
mkdir -p "$CONTENTS/MacOS"
mkdir -p "$CONTENTS/Resources"
cp .build/debug/OllamaBob "$CONTENTS/MacOS/OllamaBob"

# Info.plist is (re)generated here from source so it survives
# `rm -rf build/`. TCC usage strings explain why Bob might touch
# protected folders when the user asks him to — without these macOS
# shows a blank prompt on first access.
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>OllamaBob</string>
    <key>CFBundleIdentifier</key>
    <string>com.zack.OllamaBob</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OllamaBob</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.55</string>
    <key>CFBundleVersion</key>
    <string>155</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>OllamaBob reads and writes files on your Desktop when you ask Bob to — for example, "save this file to the desktop" or "what's on my desktop?".</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>OllamaBob reads and writes files in your Documents folder when you ask Bob to — for example, "read my notes" or "save this report to Documents".</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>OllamaBob reads and writes files in your Downloads folder when you ask Bob to — for example, "what did I download today?" or "move this zip to Downloads".</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>OllamaBob reads and writes files on external drives (USB sticks, SD cards) when you ask Bob to work with files stored there.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>OllamaBob drives other Mac apps (Mail, Calendar, Reminders, Contacts, Music, Finder, System Events) via AppleScript when you ask Bob to — for example, "do I have new mail?", "triage my unread mail", or "add a reminder to call mom". Every AppleScript run requires your approval in Bob first.</string>
    <key>NSContactsUsageDescription</key>
    <string>OllamaBob reads your Contacts when you ask Bob to look up a person's phone, email, or address.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>OllamaBob reads and writes events in Calendar when you ask Bob to check your schedule or add an event.</string>
    <key>NSRemindersUsageDescription</key>
    <string>OllamaBob reads and writes Reminders when you ask Bob to check your to-dos or add a new reminder.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>OllamaBob captures screen content only when you explicitly ask Bob to look at the active window. The capture is OCR'd locally; the image and text never leave this machine.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>OllamaBob recognizes speech locally so you can talk to Bob via the push-to-talk hotkey. Recognition runs on-device by default; nothing leaves this Mac.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OllamaBob records microphone input only while you hold the push-to-talk hotkey. Audio is processed on-device and discarded after recognition.</string>
</dict>
</plist>
PLIST

# Copy the SPM-generated resource bundle (sprites, etc.) so Bundle.module
# can find it at runtime. Bundle.module searches Bundle.main.resourceURL
# first, which on macOS .app bundles resolves to Contents/Resources.
RESOURCE_BUNDLE=".build/debug/OllamaBob_OllamaBob.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    rm -rf "$CONTENTS/Resources/OllamaBob_OllamaBob.bundle"
    cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/OllamaBob_OllamaBob.bundle"
fi

# App icon — copy AppIcon.icns into Contents/Resources so the Info.plist
# CFBundleIconFile/CFBundleIconName entries can resolve it.
APP_ICNS="OllamaBob/Resources/AppIcon/AppIcon.icns"
if [[ -f "$APP_ICNS" ]]; then
    cp "$APP_ICNS" "$CONTENTS/Resources/AppIcon.icns"
fi

# Re-sign so macOS launchd spawns the app after new framework imports.
# Without this, `open` can fail with "Launchd job spawn failed" (error 162)
# when a freshly-rebuilt binary gains a new linked framework (AVFoundation,
# EventKit, etc.) — the cached signature becomes invalid.
#
# Prefer a stable code-signing identity over ad-hoc (`-`) signing: ad-hoc
# signatures have NO stable identity, so every rebuild invalidates Keychain
# "Always Allow" ACLs and the user gets re-prompted for every secret on
# every launch. A stable identity (e.g. "Apple Development: ...") makes the
# bundle's Designated Requirement constant across rebuilds, so once the user
# clicks "Always Allow" the ACL persists.
#
# We do NOT silently fall back to ad-hoc on transient signing failures —
# that would silently invalidate the user's Keychain grants. If the chosen
# identity is configured but signing fails for any reason, we surface the
# error so the user can fix it, rather than secretly downgrading.
SIGNING_IDENTITY="${OLLAMABOB_SIGNING_IDENTITY:-Apple Development}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
    if ! codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE" 2>&1; then
        echo "ERROR: codesign with '$SIGNING_IDENTITY' failed." >&2
        echo "       Refusing to silently fall back to ad-hoc — that would" >&2
        echo "       invalidate your Keychain 'Always Allow' grants and re-prompt" >&2
        echo "       for every secret on next launch." >&2
        echo "       Fix the signing issue, or set OLLAMABOB_SIGNING_IDENTITY=- to opt into ad-hoc." >&2
        exit 1
    fi
    echo "Signed with: $SIGNING_IDENTITY"
elif [[ "$SIGNING_IDENTITY" == "-" ]]; then
    # User explicitly opted into ad-hoc. Honor it but warn.
    codesign --force --deep --sign - "$APP_BUNDLE" > /dev/null 2>&1 || true
    echo "WARNING: ad-hoc signed (OLLAMABOB_SIGNING_IDENTITY=-). Keychain prompts will recur every build." >&2
else
    echo "WARNING: no codesigning identity matching '$SIGNING_IDENTITY' found." >&2
    echo "         Falling back to ad-hoc signing — Keychain prompts will recur every build." >&2
    echo "         To stop this, install an Apple Development certificate, or set" >&2
    echo "         OLLAMABOB_SIGNING_IDENTITY to an identity from \`security find-identity -v -p codesigning\`." >&2
    codesign --force --deep --sign - "$APP_BUNDLE" > /dev/null 2>&1 || true
fi

echo "Build complete: $APP_BUNDLE"

if [[ "$1" == "--run" || "$1" == "-r" ]]; then
    echo "Launching..."
    open "$APP_BUNDLE"
fi
