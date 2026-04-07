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
