#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
app_dir=".build/Worklink.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
go build -trimpath -o "$app_dir/Contents/Resources/worklink" ./cmd/worklink
GOOS=darwin GOARCH=arm64 go build -trimpath -o "$app_dir/Contents/Resources/worklink-darwin-arm64" ./cmd/worklink
GOOS=darwin GOARCH=amd64 go build -trimpath -o "$app_dir/Contents/Resources/worklink-darwin-amd64" ./cmd/worklink
xcrun swiftc -O -swift-version 5 -target "$(uname -m)-apple-macosx14.0" macos/*.swift -o "$app_dir/Contents/MacOS/Worklink"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.worklink.app</string>
<key>CFBundleName</key><string>Worklink</string>
<key>CFBundleDisplayName</key><string>Worklink</string>
<key>CFBundleExecutable</key><string>Worklink</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app_dir"
printf '%s\n' "$app_dir"
