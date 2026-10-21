#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --cache-path .build/cache --config-path .build/config --security-path .build/security
mkdir -p build/Lumen.app/Contents/MacOS build/Lumen.app/Contents/Resources
cp .build/release/Lumen build/Lumen.app/Contents/MacOS/Lumen
cat > build/Lumen.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Lumen</string>
<key>CFBundleDisplayName</key><string>Lumen</string>
<key>CFBundleIdentifier</key><string>local.lumen.desktop</string>
<key>CFBundleExecutable</key><string>Lumen</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Lumen uses your microphone when you start Listen or voice-follow in the teleprompter.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Lumen recognizes speech on this Mac when you start Listen or voice-follow in the teleprompter.</string>
<key>NSAudioCaptureUsageDescription</key><string>Lumen listens to system audio only when you choose System audio and start Listen.</string>
<key>NSScreenCaptureUsageDescription</key><string>Lumen captures your selected screen when you request a screenshot or start automatic screen explanations.</string>
</dict></plist>
PLIST
lumen_signing_identity="${LUMEN_SIGNING_IDENTITY:-}"
if [ -z "$lumen_signing_identity" ]; then
    lumen_signing_candidates="$(security find-identity -v -p codesigning)"
    lumen_signing_identity="$(printf '%s\n' "$lumen_signing_candidates" | awk '/"Developer ID Application:/{print $2; exit}')"
    if [ -z "$lumen_signing_identity" ]; then
        lumen_signing_identity="$(printf '%s\n' "$lumen_signing_candidates" | awk '/"Apple Development:/{print $2; exit}')"
    fi
fi
if [ -z "$lumen_signing_identity" ]; then
    lumen_signing_identity="-"
    printf 'No development certificate found; this ad-hoc build may need screen access granted again after updates.\n' >&2
fi
codesign --force --sign "$lumen_signing_identity" --identifier local.lumen.desktop --timestamp=none build/Lumen.app
codesign --verify --strict build/Lumen.app
printf 'Built %s/build/Lumen.app\n' "$PWD"
