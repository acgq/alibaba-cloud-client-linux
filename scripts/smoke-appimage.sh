#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

APPIMAGE="${ALIBABA_SMOKE_APPIMAGE:-$REPO_DIR/dist/Alibaba_Cloud_Client-2.3.3-x86_64.AppImage}"
SMOKE_SECONDS="${ALIBABA_SMOKE_SECONDS:-15}"
require_file "$APPIMAGE"
require_command timeout

smoke_dir="$(mktemp -d /tmp/alibaba-cloud-client-smoke.XXXXXX)"
trap 'rm -rf "$smoke_dir"' EXIT
smoke_appimage="$smoke_dir/Alibaba_Cloud_Client-2.3.3-x86_64.AppImage"
cp "$APPIMAGE" "$smoke_appimage"
chmod 0755 "$smoke_appimage"
mkdir -p "$smoke_appimage.home" "$smoke_appimage.config"

info "Starting the AppImage for ${SMOKE_SECONDS}s with portable test data"
set +e
APPIMAGE_EXTRACT_AND_RUN=1 timeout --signal=TERM "${SMOKE_SECONDS}s" \
    "$smoke_appimage" --ozone-platform=x11 --disable-gpu \
    >"$smoke_dir/stdout.log" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
    sed -n '1,240p' "$smoke_dir/stdout.log" >&2
    die "AppImage exited unexpectedly with status $status"
fi

app_log="$smoke_appimage.home/.aliyun/logs/alibaba-cloud-client.log"
require_file "$app_log"
grep -q 'application started' "$app_log" \
    || die "Startup log does not contain the application-started marker"
grep -q 'home window' "$app_log" \
    || die "Startup log does not contain the home-window marker"
if grep -Eqi '(ERR_DLOPEN_FAILED|invalid ELF|wrong ELF|Cannot find module.*\.node|UnhandledPromiseRejection)' \
    "$smoke_dir/stdout.log" "$app_log"; then
    sed -n '1,240p' "$smoke_dir/stdout.log" >&2
    die "Startup log contains a native-module or unhandled-promise error"
fi

info "AppImage startup smoke test passed"
