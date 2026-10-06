#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
renderer="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [ ! -x "$renderer" ]; then
  printf '%s\n' 'Regenerating icon assets requires Xcode 26+ with Icon Composer.' >&2
  exit 1
fi
iconset=.build/Worklink.iconset
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=''
    if [ "$scale" = 2 ]; then suffix='@2x'; fi
    "$renderer" assets/Worklink.icon --export-image \
      --output-file "$iconset/icon_${size}x${size}$suffix.png" --platform macOS \
      --rendition Default --width "$size" --height "$size" --scale "$scale" >/dev/null
  done
done
iconutil -c icns "$iconset" -o .build/Worklink.icns
cp .build/Worklink.icns assets/Worklink.icns
cp "$iconset/icon_512x512@2x.png" assets/worklink-preview.png
