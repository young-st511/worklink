#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
renderer="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [ ! -x "$renderer" ]; then
  printf '%s\n' 'Icon previews require Xcode 26+ with Icon Composer.' >&2
  exit 1
fi
mkdir -p .build/icon-previews
for appearance in Default Dark ClearLight ClearDark TintedLight TintedDark; do
  "$renderer" assets/Worklink.icon --export-image \
    --output-file ".build/icon-previews/$appearance.png" --platform macOS \
    --rendition "$appearance" --width 1024 --height 1024 --scale 1 \
    --tint-color 0.55 --tint-strength 0.65
done
for size in 16 32 64; do
  "$renderer" assets/Worklink.icon --export-image \
    --output-file ".build/icon-previews/size-$size.png" --platform macOS \
    --rendition Default --width "$size" --height "$size" --scale 2
done
