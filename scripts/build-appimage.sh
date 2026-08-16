#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

APP_DIR="${ALIBABA_APP_DIR:-$REPO_DIR/alibaba-cloud-client-app}"
APPDIR="${ALIBABA_APPIMAGE_DIR:-$REPO_DIR/build/appimage.AppDir}"
DIST_DIR="${ALIBABA_DIST_DIR:-$REPO_DIR/dist}"
OUTPUT="$DIST_DIR/Alibaba_Cloud_Client-2.3.3-x86_64.AppImage"

resolve_appimagetool() {
    if [ -n "${APPIMAGETOOL:-}" ]; then
        [ -x "$APPIMAGETOOL" ] || die "APPIMAGETOOL is not executable: $APPIMAGETOOL"
        printf '%s\n' "$APPIMAGETOOL"
        return
    fi
    command -v appimagetool >/dev/null 2>&1 \
        || die "appimagetool is required; install it or set APPIMAGETOOL=/path/to/appimagetool"
    command -v appimagetool
}

require_dir "$APP_DIR"
require_file "$APP_DIR/.linux/build-info.json"
require_file "$REPO_DIR/packaging/appimage/AppRun"
appimagetool="$(resolve_appimagetool)"

info "Preparing AppDir"
rm -rf "$APPDIR"
mkdir -p \
    "$APPDIR/opt/alibaba-cloud-client" \
    "$APPDIR/usr/share/applications" \
    "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
    "$DIST_DIR"
cp -a "$APP_DIR/." "$APPDIR/opt/alibaba-cloud-client/"
cp "$REPO_DIR/packaging/appimage/AppRun" "$APPDIR/AppRun"
chmod 0755 "$APPDIR/AppRun"

sed 's/^Exec=.*/Exec=AppRun %U/' \
    "$REPO_DIR/packaging/alibaba-cloud-client.desktop" \
    > "$APPDIR/alibaba-cloud-client.desktop"
cp "$APPDIR/alibaba-cloud-client.desktop" \
    "$APPDIR/usr/share/applications/alibaba-cloud-client.desktop"
cp "$APP_DIR/.linux/icon.png" "$APPDIR/alibaba-cloud-client.png"
cp "$APP_DIR/.linux/icon.png" "$APPDIR/.DirIcon"
cp "$APP_DIR/.linux/icon.png" \
    "$APPDIR/usr/share/icons/hicolor/256x256/apps/alibaba-cloud-client.png"

rm -f "$OUTPUT"
info "Building AppImage"
ARCH=x86_64 VERSION=2.3.3 "$appimagetool" --no-appstream "$APPDIR" "$OUTPUT"
chmod 0755 "$OUTPUT"
info "Built AppImage: $OUTPUT"
