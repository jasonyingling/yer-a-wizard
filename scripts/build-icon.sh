#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/WandIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/wand-icon-final.png --out ".build/WandIcon.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" Assets/wand-icon-final.png --out ".build/WandIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/WandIcon.iconset -o Assets/WandIcon.icns
