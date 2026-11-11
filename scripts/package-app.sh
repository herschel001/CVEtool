#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox -c debug
mkdir -p build/CVEtool.app/Contents/MacOS build/CVEtool.app/Contents/Resources
swiftc Sources/CVEtoolApp/AppIcon.swift scripts/generate-icons.swift -o build/generate-icons
build/generate-icons build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
cp build/AppIcon.icns build/CVEtool.app/Contents/Resources/AppIcon.icns
cp .build/debug/CVEtool build/CVEtool.app/Contents/MacOS/CVEtool
cp Support/Info.plist build/CVEtool.app/Contents/Info.plist
codesign --force --sign - build/CVEtool.app
xattr -cr build/CVEtool.app 2>/dev/null || true
touch build/CVEtool.app
echo "built $(pwd)/build/CVEtool.app"
