#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p '.build/module-cache' 'Yer a Wizard.app/Contents/MacOS'
if [[ ! -f Assets/WandIcon.icns || Assets/wand-icon-final.png -nt Assets/WandIcon.icns ]]; then bash scripts/build-icon.sh; fi
mkdir -p 'Yer a Wizard.app/Contents/Resources'
cp Assets/WandIcon.icns 'Yer a Wizard.app/Contents/Resources/WandIcon.icns'
swiftc -O -module-cache-path .build/module-cache Sources/AppMenu.swift Sources/Tracker.swift Sources/Spells.swift Sources/PumpkinGame.swift Sources/WandColor.swift Sources/VoiceControl.swift Sources/MagicCanvas.swift Sources/main.swift -o .build/YerAWizard -framework Cocoa -framework AVFoundation -framework CoreImage -framework SceneKit -framework Security
cp .build/YerAWizard 'Yer a Wizard.app/Contents/MacOS/YerAWizard'
cat > 'Yer a Wizard.app/Contents/Info.plist' <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>YerAWizard</string>
<key>CFBundleIdentifier</key><string>local.yer-a-wizard.studio</string>
<key>CFBundleName</key><string>Yer a Wizard</string>
<key>CFBundleIconFile</key><string>WandIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSCameraUsageDescription</key><string>Track the reflective wand tip and turn its movement into drawings. Camera frames stay on this Mac.</string>
<key>NSMicrophoneUsageDescription</key><string>When voice mode is enabled and listening, send your microphone audio to OpenAI to change the wand stream color with your voice.</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
EOF
codesign --force --sign - 'Yer a Wizard.app'
