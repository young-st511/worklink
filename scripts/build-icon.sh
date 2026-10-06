#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
resources="${1:-.build/Worklink.app/Contents/Resources}"
mkdir -p "$resources" .build
# Remove only generated icon resources so switching build modes cannot leave stale assets.
rm -f "$resources/Assets.car" "$resources/Worklink.icns" .build/icon-info.plist
if [ "${WORKLINK_LEGACY_ICON:-0}" != "1" ] && xcrun --find ictool >/dev/null 2>&1; then
  xcrun actool assets/Worklink.icon --compile "$resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon Worklink \
    --output-partial-info-plist .build/icon-info.plist --output-format human-readable-text
else
  cat > .build/icon-info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIconFile</key><string>Worklink</string></dict></plist>
PLIST
  printf '%s\n' 'Icon Composer compiler unavailable or legacy build requested: using bundled icns.'
fi
# actool emits a small compatibility stub; supply the complete 16–1024px icon instead.
cp assets/Worklink.icns "$resources/Worklink.icns"
