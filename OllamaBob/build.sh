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
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "Build complete: $APP_BUNDLE"

if [[ "$1" == "--run" || "$1" == "-r" ]]; then
    echo "Launching..."
    open "$APP_BUNDLE"
fi
