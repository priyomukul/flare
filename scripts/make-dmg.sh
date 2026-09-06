#!/usr/bin/env bash
# Builds a drag-and-drop dist/Flare-<version>.dmg from dist/Flare.app.
# hdiutil, Finder and AppKit only — no third-party tooling.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="dist/Flare.app"
[ -d "$APP" ] || { echo "missing $APP — run \`make app\` first" >&2; exit 1; }

VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
VOLUME="Flare $VERSION"
DMG="dist/Flare-$VERSION.dmg"

WORK=$(mktemp -d)
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"
MOUNT=""
cleanup() {
  [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> staging $VOLUME"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Flare.app"
ln -s /Applications "$STAGE/Applications"

# Background at 1x and 2x, combined into the multi-representation TIFF Finder
# needs to pick the Retina one.
swift scripts/dmg-background.swift "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
         -out "$STAGE/.background/background.tiff" >/dev/null

# hdiutil sizes tightly; leave room for the .DS_Store Finder is about to write.
SIZE=$(( $(du -sm "$STAGE" | cut -f1) + 60 ))

echo "==> creating writable image (${SIZE}m)"
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME" -fs HFS+ \
               -format UDRW -size "${SIZE}m" -ov "$RW" >/dev/null

# Mount under /Volumes: Finder names a disk after its mount point, so a custom
# -mountpoint would leave `tell disk "Flare 1.0.0"` unable to find it. Read the
# name back, since macOS renames on collision with an already-mounted volume.
MOUNT=$(hdiutil attach "$RW" -nobrowse -noverify -noautoopen | grep -o '/Volumes/.*$' | tail -1)
[ -n "$MOUNT" ] || { echo "could not mount the writable image" >&2; exit 1; }
MOUNTED_VOLUME=$(basename "$MOUNT")

echo "==> arranging the window"
# Finder scripting needs Automation permission for whatever is running this, and
# osascript exits 0 even when Finder refuses — so the .DS_Store it should have
# written is the real test. Without it the DMG still works, just unstyled.
osascript >/dev/null 2>"$WORK/osascript.err" <<APPLESCRIPT || true
tell application "Finder"
  tell disk "$MOUNTED_VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {240, 140, 840, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Flare.app" of container window to {150, 180}
    set position of item "Applications" of container window to {450, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# Both of these have to come after Finder: opening the window deletes any
# .VolumeIcon.icns already on the volume, and closing it rewrites the root's
# FinderInfo and clears the custom-icon bit.
cp Resources/Flare.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" || echo "    (could not set the custom volume icon bit)"

if [ ! -f "$MOUNT/.DS_Store" ]; then
  echo "    (Finder did not write a layout — shipping an unstyled but working DMG)"
  [ -s "$WORK/osascript.err" ] && sed 's/^/    /' "$WORK/osascript.err"
fi

sync
for _ in 1 2 3 4 5; do
  hdiutil detach "$MOUNT" -quiet && { MOUNT=""; break; } || sleep 1
done

echo "==> compressing"
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
codesign --force --sign - "$DMG"

echo
echo "$DMG"
echo "  size:   $(du -h "$DMG" | cut -f1)"
echo "  sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
