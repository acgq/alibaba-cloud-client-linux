#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

APP_DIR="${ALIBABA_APP_DIR:-$REPO_DIR/alibaba-cloud-client-app}"
BUILD_DIR="${ALIBABA_PACMAN_BUILD_DIR:-$REPO_DIR/build/pacman}"
DIST_DIR="${ALIBABA_DIST_DIR:-$REPO_DIR/dist}"

require_command makepkg
require_dir "$APP_DIR"
require_file "$APP_DIR/.linux/build-info.json"
require_file "$REPO_DIR/packaging/PKGBUILD"

info "Preparing pacman package workspace"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/payload/app" "$BUILD_DIR/payload/icons" "$DIST_DIR"
cp -a "$APP_DIR/." "$BUILD_DIR/payload/app/"
cp "$REPO_DIR/packaging/PKGBUILD" "$BUILD_DIR/PKGBUILD"
cp "$REPO_DIR/packaging/alibaba-cloud-client.desktop" \
    "$BUILD_DIR/payload/alibaba-cloud-client.desktop"
cp -a "$APP_DIR/.linux/icons/." "$BUILD_DIR/payload/icons/"

cat > "$BUILD_DIR/payload/alibaba-cloud-client" <<'SH'
#!/bin/bash
set -Eeuo pipefail
exec /opt/alibaba-cloud-client/start.sh "$@"
SH
chmod 0755 "$BUILD_DIR/payload/alibaba-cloud-client"

(
    cd "$BUILD_DIR"
    makepkg --force --nodeps --noconfirm
)

package_file="$(find "$BUILD_DIR" -maxdepth 1 -type f -name 'alibaba-cloud-client-2.3.3-1-x86_64.pkg.tar.*' -print -quit)"
require_file "$package_file"
cp "$package_file" "$DIST_DIR/"
ln -sfn "$(basename "$package_file")" "$DIST_DIR/alibaba-cloud-client-latest.pkg.tar.zst"
info "Built pacman package: $DIST_DIR/$(basename "$package_file")"
