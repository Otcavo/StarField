#!/bin/bash
# Builds Starfield.saver from source/Starfield.swift, with the Art and data folders packed inside it.
# Run it from anywhere:  ./build-saver.sh
# It builds build/Starfield.saver and installs it into ~/Library/Screen Savers.
set -euo pipefail
cd "$(dirname "$0")"

NAME="Starfield"
OUT="build/$NAME.saver"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "Compiling..."
swiftc -O -D SCREENSAVER -parse-as-library -module-name StarfieldSaver -emit-library \
    -o "$OUT/Contents/MacOS/$NAME" source/Starfield.swift

echo "Copying art and data..."
cp -R Art data "$OUT/Contents/Resources/"

# System Settings picture: Art/thumbnail.png (90x58) and Art/thumbnail2x.png (180x116), if present.
# They have to sit directly in Resources, and macOS needs the Retina one named thumbnail@2x.png.
if [ -f "Art/thumbnail.png" ]; then cp "Art/thumbnail.png" "$OUT/Contents/Resources/thumbnail.png"; fi
if [ -f "Art/thumbnail2x.png" ]; then
    cp "Art/thumbnail2x.png" "$OUT/Contents/Resources/thumbnail@2x.png"
elif [ -f "Art/thumbnail@2x.png" ]; then
    cp "Art/thumbnail@2x.png" "$OUT/Contents/Resources/thumbnail@2x.png"
fi

cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Starfield</string>
    <key>CFBundleIdentifier</key>
    <string>local.starfield.saver</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Starfield</string>
    <key>CFBundleDisplayName</key>
    <string>Starfield</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSPrincipalClass</key>
    <string>StarfieldSaverView</string>
</dict>
</plist>
PLIST

echo "Signing..."
codesign --force --sign - "$OUT"

echo "Installing..."
mkdir -p "$HOME/Library/Screen Savers"
rm -rf "$HOME/Library/Screen Savers/$NAME.saver"
cp -R "$OUT" "$HOME/Library/Screen Savers/"

# Make macOS reload screen savers in case an older version is still loaded
killall legacyScreenSaver 2>/dev/null || true

echo "Installed $NAME.saver. Quit and reopen System Settings, then choose Starfield under Screen Saver."