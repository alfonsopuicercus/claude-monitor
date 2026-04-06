#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")"; pwd)"
APP_NAME="Claude Monitor"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "Building Claude Monitor..."
cd "$PROJECT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Helpers"

cp ".build/release/ClaudeMonitor" "$CONTENTS/MacOS/$APP_NAME"
cp ".build/release/claude-monitor-bridge" "$CONTENTS/Helpers/claude-monitor-bridge"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Claude Monitor</string>
    <key>CFBundleExecutable</key>
    <string>Claude Monitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.alfonsopuicercus.claude-monitor</string>
    <key>CFBundleName</key>
    <string>Claude Monitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
PLIST

# Ad-hoc code sign (required for macOS to launch unsigned apps)
echo "Signing..."
codesign --sign - --force --deep "$APP_DIR"

echo ""
echo "✓ Build complete: $APP_DIR"
echo ""
echo "To install:"
echo "  cp -R \"$APP_DIR\" /Applications/"
echo "  open \"/Applications/$APP_NAME.app\""
