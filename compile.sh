#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TouchBrightness"
APP_BUNDLE="${APP_NAME}.app"

echo "Compiling ${APP_NAME}..."
swiftc -O \
    -framework Cocoa \
    -framework ServiceManagement \
    -o "${APP_NAME}" \
    Sources/main.swift

echo "Creating ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"

mv "${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Copy all localization files
for lproj in Sources/*.lproj; do
    lang=$(basename "$lproj")
    mkdir -p "${APP_BUNDLE}/Contents/Resources/${lang}"
    cp "${lproj}/Localizable.strings" "${APP_BUNDLE}/Contents/Resources/${lang}/"
done

# Copy app icon
cp Sources/AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"

# Create Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TouchBrightness</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.touchbrightness</string>
    <key>CFBundleName</key>
    <string>TouchBrightness</string>
    <key>CFBundleDisplayName</key>
    <string>触控栏亮度</string>
    <key>CFBundleVersion</key>
    <string>1.4.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "Done! Run with: open ${APP_BUNDLE}"
