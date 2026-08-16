#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

APP_DIR="${ALIBABA_APP_DIR:-$REPO_DIR/alibaba-cloud-client-app}"
BUILD_DIR="${ALIBABA_DEB_BUILD_DIR:-$REPO_DIR/build/deb}"
DIST_DIR="${ALIBABA_DIST_DIR:-$REPO_DIR/dist}"
OUTPUT="$DIST_DIR/alibaba-cloud-client_2.3.3-1_amd64.deb"

for command in ar md5sum tar xz; do
    require_command "$command"
done
require_dir "$APP_DIR"
require_file "$APP_DIR/.linux/build-info.json"
require_file "$REPO_DIR/packaging/alibaba-cloud-client.desktop"

info "Preparing Debian package workspace"
rm -rf "$BUILD_DIR"
mkdir -p \
    "$BUILD_DIR/control" \
    "$BUILD_DIR/data/opt/alibaba-cloud-client" \
    "$BUILD_DIR/data/usr/bin" \
    "$BUILD_DIR/data/usr/share/applications" \
    "$DIST_DIR"

cp -a "$APP_DIR/." "$BUILD_DIR/data/opt/alibaba-cloud-client/"
chmod 4755 "$BUILD_DIR/data/opt/alibaba-cloud-client/chrome-sandbox"
cp "$REPO_DIR/packaging/alibaba-cloud-client.desktop" \
    "$BUILD_DIR/data/usr/share/applications/alibaba-cloud-client.desktop"

cat > "$BUILD_DIR/data/usr/bin/alibaba-cloud-client" <<'SH'
#!/bin/bash
set -Eeuo pipefail
exec /opt/alibaba-cloud-client/start.sh "$@"
SH
chmod 0755 "$BUILD_DIR/data/usr/bin/alibaba-cloud-client"

for size in 16 32 48 64 128 256 512; do
    install -Dm644 "$APP_DIR/.linux/icons/${size}x${size}.png" \
        "$BUILD_DIR/data/usr/share/icons/hicolor/${size}x${size}/apps/alibaba-cloud-client.png"
done

installed_size="$(du -sk "$BUILD_DIR/data" | awk '{print $1}')"
cat > "$BUILD_DIR/control/control" <<EOF
Package: alibaba-cloud-client
Version: 2.3.3-1
Architecture: amd64
Maintainer: acgq <chen330021@live.com>
Installed-Size: $installed_size
Depends: libasound2 | libasound2t64, libatk-bridge2.0-0, libcups2 | libcups2t64, libdrm2, libgbm1, libgtk-3-0 | libgtk-3-0t64, libnss3, libxkbcommon0, libxss1, libxtst6
Recommends: xdg-utils
Section: utils
Priority: optional
Homepage: https://github.com/acgq/alibaba-cloud-client-linux
Description: Alibaba Cloud Client repackaged for Linux
 Unofficial Linux conversion of the official Alibaba Cloud Client macOS DMG.
EOF

(
    cd "$BUILD_DIR/data"
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum \
        | sed 's#  \./#  #' > "$BUILD_DIR/control/md5sums"
)

printf '2.0\n' > "$BUILD_DIR/debian-binary"
tar --owner=0 --group=0 --numeric-owner -C "$BUILD_DIR/control" \
    -cJf "$BUILD_DIR/control.tar.xz" .
tar --owner=0 --group=0 --numeric-owner -C "$BUILD_DIR/data" \
    -cJf "$BUILD_DIR/data.tar.xz" .

rm -f "$OUTPUT"
(
    cd "$BUILD_DIR"
    ar rcs "$OUTPUT" debian-binary control.tar.xz data.tar.xz
)
chmod 0644 "$OUTPUT"

[ "$(ar t "$OUTPUT" | tr '\n' ' ')" = "debian-binary control.tar.xz data.tar.xz " ] \
    || die "Invalid Debian archive member layout"
ar p "$OUTPUT" data.tar.xz > "$BUILD_DIR/verify-data.tar.xz"
tar -tJf "$BUILD_DIR/verify-data.tar.xz" > "$BUILD_DIR/verify-data.list"
grep -qx './usr/share/applications/alibaba-cloud-client.desktop' \
    "$BUILD_DIR/verify-data.list" \
    || die "Debian package is missing its desktop entry"
info "Built Debian package: $OUTPUT"
