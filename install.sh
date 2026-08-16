#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
. "$REPO_DIR/scripts/lib/common.sh"
. "$REPO_DIR/scripts/lib/node-runtime.sh"

EXPECTED_APP_VERSION="2.3.3"
EXPECTED_ELECTRON_VERSION="19.1.9"
BETTER_SQLITE3_VERSION="12.5.0"
NODE_PTY_VERSION="1.1.0-beta35"

WORK_DIR="${ALIBABA_WORK_DIR:-$REPO_DIR/build/work}"
CACHE_DIR="${ALIBABA_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/alibaba-cloud-client-linux}"
INSTALL_DIR="${ALIBABA_INSTALL_DIR:-$REPO_DIR/alibaba-cloud-client-app}"
TOOLS_DIR="$REPO_DIR/build-tools"

usage() {
    cat <<'USAGE'
Usage: ./install.sh [/path/to/alibaba-cloud-client.dmg]

Environment overrides:
  ALIBABA_NODE_SOURCE       Existing Node.js >=22.12 runtime directory
  ALIBABA_ELECTRON_ZIP      Existing electron-v19.1.9-linux-x64.zip
  ALIBABA_CACHE_DIR         Download cache directory
  ALIBABA_WORK_DIR          Temporary build directory
  ALIBABA_INSTALL_DIR       Generated application directory
  ELECTRON_MIRROR           Electron release mirror root
USAGE
}

discover_dmg() {
    local explicit="${1:-}"
    local candidates=()

    if [ -n "$explicit" ]; then
        require_file "$explicit"
        printf '%s\n' "$explicit"
        return
    fi

    while IFS= read -r -d '' candidate; do
        candidates+=("$candidate")
    done < <(find "$REPO_DIR" -maxdepth 1 -type f -name '*.dmg*' -print0)

    [ "${#candidates[@]}" -gt 0 ] || die "No DMG found; pass its path to install.sh"
    [ "${#candidates[@]}" -eq 1 ] \
        || die "Multiple DMG files found; pass the intended path explicitly"
    printf '%s\n' "${candidates[0]}"
}

run_asar() {
    local cli="$TOOLS_DIR/node_modules/@electron/asar/bin/asar.js"
    [ -f "$cli" ] || cli="$TOOLS_DIR/node_modules/@electron/asar/bin/asar.mjs"
    require_file "$cli"
    node "$cli" "$@"
}

ensure_build_tools() {
    info "Installing locked build tools"
    if [ -f "$TOOLS_DIR/package-lock.json" ]; then
        npm ci --prefix "$TOOLS_DIR" --ignore-scripts --no-audit --no-fund
    else
        warn "package-lock.json is missing; generating it from exact package versions"
        npm install --prefix "$TOOLS_DIR" --ignore-scripts --no-audit --no-fund
    fi
}

extract_dmg() {
    local dmg="$1"
    local extract_dir="$WORK_DIR/dmg"

    info "Extracting official DMG"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    7z x -y -o"$extract_dir" "$dmg" >/dev/null \
        || die "7z could not extract the DMG"

    find "$extract_dir" -type d -name 'Alibaba Cloud Client.app' -print -quit
}

validate_upstream() {
    local app_dir="$1"
    local package_json="$app_dir/Contents/Resources/package.json"
    local info_plist="$app_dir/Contents/Info.plist"
    local mac_binary="$app_dir/Contents/MacOS/Alibaba Cloud Client"
    local app_version
    local electron_version
    local bundle_version

    require_file "$package_json"
    require_file "$info_plist"
    require_file "$mac_binary"
    require_file "$app_dir/Contents/Resources/app.asar"

    app_version="$(json_value "$package_json" version)"
    electron_version="$(json_value "$package_json" devDependencies.electron)"
    bundle_version="$(python3 - "$info_plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as handle:
    print(plistlib.load(handle)["CFBundleShortVersionString"])
PY
)"

    [ "$app_version" = "$EXPECTED_APP_VERSION" ] \
        || die "Unsupported app version: $app_version (expected $EXPECTED_APP_VERSION)"
    [ "$bundle_version" = "$EXPECTED_APP_VERSION" ] \
        || die "DMG bundle version mismatch: $bundle_version"
    [ "$electron_version" = "$EXPECTED_ELECTRON_VERSION" ] \
        || die "Unsupported Electron version: $electron_version (expected $EXPECTED_ELECTRON_VERSION)"
    file "$mac_binary" | grep -q 'x86_64' \
        || die "The DMG does not contain an x86_64 application"

    info "Validated Alibaba Cloud Client $app_version / Electron $electron_version"
}

prepare_sources() {
    local app_dir="$1"
    local resources="$app_dir/Contents/Resources"
    local extracted="$WORK_DIR/app-extracted"

    rm -rf "$extracted"
    mkdir -p "$extracted"
    info "Extracting app.asar"
    run_asar extract "$resources/app.asar" "$extracted"
    if [ -d "$resources/app.asar.unpacked" ]; then
        cp -a "$resources/app.asar.unpacked/." "$extracted/"
    fi
    require_file "$extracted/main/index.js"
}

rebuild_native_modules() {
    local extracted="$WORK_DIR/app-extracted"
    local rebuild_cli="$TOOLS_DIR/node_modules/@electron/rebuild/lib/cli.js"
    local native_dir="$extracted/main/native_modules/build/Release"
    local node_pty_source="$TOOLS_DIR/node_modules/node-pty"
    local better_source="$TOOLS_DIR/node_modules/better-sqlite3"

    require_file "$rebuild_cli"
    info "Rebuilding better-sqlite3@$BETTER_SQLITE3_VERSION and node-pty@$NODE_PTY_VERSION"
    (
        cd "$TOOLS_DIR"
        npm_config_build_from_source=true \
        npm_config_disturl=https://electronjs.org/headers \
        node "$rebuild_cli" \
            --version "$EXPECTED_ELECTRON_VERSION" \
            --force \
            --only "better-sqlite3,node-pty"
    )

    require_file "$better_source/build/Release/better_sqlite3.node"
    require_file "$node_pty_source/build/Release/pty.node"
    if [ ! -f "$node_pty_source/build/Release/spawn-helper" ]; then
        require_file "$node_pty_source/src/unix/spawn-helper.cc"
        info "Building Linux spawn-helper from node-pty source"
        g++ -O2 -Wall -Wextra \
            "$node_pty_source/src/unix/spawn-helper.cc" \
            -o "$node_pty_source/build/Release/spawn-helper"
    fi
    require_file "$node_pty_source/build/Release/spawn-helper"

    rm -rf "$extracted/main/native_modules"
    mkdir -p "$native_dir"
    cp "$better_source/build/Release/better_sqlite3.node" "$native_dir/"
    cp "$node_pty_source/build/Release/pty.node" "$native_dir/"
    cp "$node_pty_source/build/Release/spawn-helper" "$native_dir/"
    chmod 0755 "$native_dir/spawn-helper"

    rm -rf "$extracted/node_modules/node-pty"
    mkdir -p "$extracted/node_modules"
    cp -a "$node_pty_source" "$extracted/node_modules/node-pty"

    info "Applying Linux compatibility patches"
    node "$REPO_DIR/scripts/patch-linux.js" \
        "$extracted/main/index.js" \
        "$WORK_DIR/patch-report.json"
}

repack_asar() {
    local extracted="$WORK_DIR/app-extracted"
    local packed="$WORK_DIR/app.asar"
    local ordering="$WORK_DIR/app.asar.ordering"

    rm -f "$packed"
    rm -rf "$WORK_DIR/app.asar.unpacked"
    (cd "$extracted" && find . -type f -printf '%P\n' | LC_ALL=C sort) > "$ordering"
    info "Repacking app.asar"
    run_asar pack "$extracted" "$packed" \
        --ordering "$ordering" \
        --unpack '{*.node,spawn-helper}'
    require_file "$packed"
}

download_electron() {
    local zip_name="electron-v${EXPECTED_ELECTRON_VERSION}-linux-x64.zip"
    local release_root
    local zip_path
    local sums_path
    local checksum

    if [ -n "${ALIBABA_ELECTRON_ZIP:-}" ]; then
        require_file "$ALIBABA_ELECTRON_ZIP"
        cp "$ALIBABA_ELECTRON_ZIP" "$WORK_DIR/electron.zip"
        return
    fi

    if [ -n "${ELECTRON_MIRROR:-}" ]; then
        release_root="${ELECTRON_MIRROR%/}/v${EXPECTED_ELECTRON_VERSION}"
    else
        release_root="https://github.com/electron/electron/releases/download/v${EXPECTED_ELECTRON_VERSION}"
    fi
    zip_path="$CACHE_DIR/electron/$zip_name"
    sums_path="$CACHE_DIR/electron/SHASUMS256-v${EXPECTED_ELECTRON_VERSION}.txt"
    download_file "$release_root/$zip_name" "$zip_path"
    download_file "$release_root/SHASUMS256.txt" "$sums_path"

    checksum="$(awk -v file="$zip_name" '$2 == "*" file || $2 == file { print $1; exit }' "$sums_path")"
    [ -n "$checksum" ] || die "Electron checksum was not found in SHASUMS256.txt"
    verify_sha256 "$zip_path" "$checksum"
    cp "$zip_path" "$WORK_DIR/electron.zip"
}

generate_icons() {
    local app_dir="$1"
    local icon_source="$app_dir/Contents/Resources/icon.icns"
    local extract_dir="$WORK_DIR/icons"
    local largest
    local size

    require_file "$icon_source"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir" "$INSTALL_DIR/.linux/icons"
    largest="$extract_dir/source.png"
    python3 - "$icon_source" "$largest" <<'PY'
import struct
import sys

source, destination = sys.argv[1:]
data = open(source, "rb").read()
if len(data) < 8 or data[:4] != b"icns":
    raise SystemExit("Invalid ICNS file")

images = []
offset = 8
while offset + 8 <= len(data):
    length = struct.unpack(">I", data[offset + 4:offset + 8])[0]
    if length < 8 or offset + length > len(data):
        raise SystemExit("Malformed ICNS element")
    payload = data[offset + 8:offset + length]
    if payload.startswith(b"\x89PNG\r\n\x1a\n"):
        images.append(payload)
    offset += length

if not images:
    raise SystemExit("ICNS does not contain an embedded PNG")
with open(destination, "wb") as handle:
    handle.write(max(images, key=len))
PY
    require_file "$largest"
    for size in 16 32 48 64 128 256 512; do
        magick "$largest" -resize "${size}x${size}" \
            "$INSTALL_DIR/.linux/icons/${size}x${size}.png"
    done
    cp "$INSTALL_DIR/.linux/icons/256x256.png" "$INSTALL_DIR/.linux/icon.png"
}

stage_application() {
    local app_dir="$1"
    local resources="$app_dir/Contents/Resources"
    local dmg="$2"
    local dmg_sha
    local built_at

    info "Staging Linux Electron application"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    unzip -q "$WORK_DIR/electron.zip" -d "$INSTALL_DIR"
    rm -f "$INSTALL_DIR/resources/default_app.asar"
    mkdir -p "$INSTALL_DIR/resources" "$INSTALL_DIR/.linux"
    cp "$WORK_DIR/app.asar" "$INSTALL_DIR/resources/app.asar"
    if [ -d "$WORK_DIR/app.asar.unpacked" ]; then
        cp -a "$WORK_DIR/app.asar.unpacked" "$INSTALL_DIR/resources/app.asar.unpacked"
    fi
    cp "$resources/package.json" "$INSTALL_DIR/resources/package.json"
    cp "$resources/app-update.yml" "$INSTALL_DIR/resources/app-update.yml"
    cp "$WORK_DIR/patch-report.json" "$INSTALL_DIR/.linux/patch-report.json"
    cp "$REPO_DIR/launcher/start.sh.template" "$INSTALL_DIR/start.sh"
    chmod 0755 "$INSTALL_DIR/start.sh" "$INSTALL_DIR/electron"
    [ ! -f "$INSTALL_DIR/chrome-sandbox" ] || chmod 4755 "$INSTALL_DIR/chrome-sandbox"

    generate_icons "$app_dir"
    dmg_sha="$(sha256sum "$dmg" | awk '{print $1}')"
    built_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 - "$INSTALL_DIR/.linux/build-info.json" "$dmg_sha" "$built_at" <<PY
import json
import sys
path, dmg_sha, built_at = sys.argv[1:]
data = {
    "appName": "Alibaba Cloud Client",
    "appVersion": "$EXPECTED_APP_VERSION",
    "electronVersion": "$EXPECTED_ELECTRON_VERSION",
    "architecture": "x86_64",
    "betterSqlite3Version": "$BETTER_SQLITE3_VERSION",
    "nodePtyVersion": "$NODE_PTY_VERSION",
    "sourceDmgSha256": dmg_sha,
    "builtAt": built_at,
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2, ensure_ascii=False)
    handle.write("\n")
PY
}

main() {
    local dmg
    local upstream_app

    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
    esac
    [ "$(uname -m)" = "x86_64" ] || die "Only x86_64 build hosts are supported"

    for command in 7z curl unzip tar xz sha256sum python3 file ldd npm magick; do
        require_command "$command"
    done
    dmg="$(discover_dmg "${1:-}")"
    info "Source DMG: $dmg"

    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR" "$CACHE_DIR"
    ensure_managed_node "$WORK_DIR/node-runtime"
    ensure_build_tools

    upstream_app="$(extract_dmg "$dmg")"
    [ -n "$upstream_app" ] || die "Alibaba Cloud Client.app was not found in the DMG"
    validate_upstream "$upstream_app"
    prepare_sources "$upstream_app"
    rebuild_native_modules
    repack_asar
    download_electron
    stage_application "$upstream_app" "$dmg"
    "$REPO_DIR/scripts/verify-app.sh" "$INSTALL_DIR"

    info "Linux application ready: $INSTALL_DIR"
}

main "$@"
