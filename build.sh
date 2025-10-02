#!/bin/bash

# Build script for mjvoice
# Assumes Xcode 15+, macOS Sonoma+

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_NAME="mjvoice"
DMG_NAME="$APP_NAME.dmg"
DERIVED_DIR="$BUILD_DIR/DerivedData"

echo "Building $APP_NAME..."

# Clean
xcodebuild -project "$PROJECT_DIR/mjvoice.xcodeproj" -scheme mjvoice -derivedDataPath "$DERIVED_DIR" clean

# Build
xcodebuild -project "$PROJECT_DIR/mjvoice.xcodeproj" -scheme mjvoice -configuration Release -derivedDataPath "$DERIVED_DIR" build

# Find the built app
APP_PATH="$DERIVED_DIR/Build/Products/Release/mjvoice.app"
if [ ! -d "$APP_PATH" ]; then
    echo "App not found at $APP_PATH"
    exit 1
fi

echo "App built at $APP_PATH"

# Codesign (replace with your developer ID)
# codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name (TEAMID)" "$APP_PATH"

# Notarize (requires notarytool configured)

# Create DMG
echo "Creating DMG..."
# Create DMG directory
DMG_DIR="$BUILD_DIR/dmg"
mkdir -p "$DMG_DIR"
cp -r "$APP_PATH" "$DMG_DIR/"

# Create background image (placeholder - replace with actual image)
# Use a simple background; in production, create a proper PNG
echo "Preparing background image..."
BACKGROUND="$DMG_DIR/background.png"
if command -v convert >/dev/null 2>&1; then
    convert -size 800x400 xc:"#f4f6fb" -pointsize 36 -fill "#333" -gravity center -draw "text 0,0 'mjvoice\n\nDrag to Applications'" "$BACKGROUND"
else
    # Fallback: copy macOS built-in solid color if available
    SOLID="/System/Library/Desktop Pictures/Solid Colors/Silver.heic"
    if [ -f "$SOLID" ]; then
        sips -s format png "$SOLID" --out "$BACKGROUND" >/dev/null 2>&1 || true
    fi
fi

BACKGROUND_OPT=()
if [ -f "$BACKGROUND" ]; then
    BACKGROUND_OPT=(--background "$BACKGROUND")
fi

# Use create-dmg for professional DMG
if command -v create-dmg >/dev/null 2>&1; then
    if [ ${#BACKGROUND_OPT[@]} -gt 0 ]; then
        create-dmg \
            --volname "mjvoice" \
            --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
            "${BACKGROUND_OPT[@]}" \
            --window-pos 200 120 \
            --window-size 800 400 \
            --icon-size 100 \
            --icon "mjvoice.app" 200 190 \
            --hide-extension "mjvoice.app" \
            --app-drop-link 600 185 \
            "$BUILD_DIR/$DMG_NAME" \
            "$DMG_DIR/"
    else
        create-dmg \
            --volname "mjvoice" \
            --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
            --window-pos 200 120 \
            --window-size 800 400 \
            --icon-size 100 \
            --icon "mjvoice.app" 200 190 \
            --hide-extension "mjvoice.app" \
            --app-drop-link 600 185 \
            "$BUILD_DIR/$DMG_NAME" \
            "$DMG_DIR/"
    fi
else
    # Fallback to hdiutil
    hdiutil create -volname "mjvoice" -srcfolder "$DMG_DIR" -ov -format UDZO "$BUILD_DIR/$DMG_NAME"
fi

echo "DMG created at $BUILD_DIR/$DMG_NAME"

# Notarize DMG if needed
# xcrun notarytool submit "$BUILD_DIR/$DMG_NAME" --wait --keychain-profile "notary"
echo "Done."
