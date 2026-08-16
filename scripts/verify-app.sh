#!/bin/bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

APP_DIR="${1:-$REPO_DIR/alibaba-cloud-client-app}"
RESOURCES="$APP_DIR/resources"
UNPACKED="$RESOURCES/app.asar.unpacked"

require_file "$APP_DIR/electron"
require_file "$RESOURCES/app.asar"
require_file "$APP_DIR/start.sh"
require_file "$APP_DIR/.linux/build-info.json"

check_elf_x64() {
    local target="$1"
    require_file "$target"
    local description
    description="$(file -b "$target")"
    case "$description" in
        *ELF*64-bit*x86-64*) ;;
        *) die "Expected ELF x86-64 file, got '$description': $target" ;;
    esac
}

check_elf_x64 "$APP_DIR/electron"
check_elf_x64 "$UNPACKED/main/native_modules/build/Release/better_sqlite3.node"
check_elf_x64 "$UNPACKED/main/native_modules/build/Release/pty.node"
check_elf_x64 "$UNPACKED/main/native_modules/build/Release/spawn-helper"

mach_file="$(
    find "$UNPACKED" -type f -print0 2>/dev/null \
        | xargs -0 -r file \
        | grep -m1 'Mach-O' \
        | cut -d: -f1 \
        || true
)"
[ -z "$mach_file" ] || die "Mach-O executable remains in runtime payload: $mach_file"

missing="$(ldd "$APP_DIR/electron" 2>/dev/null | grep 'not found' || true)"
[ -z "$missing" ] || die "Electron has missing shared libraries:\n$missing"

for target in \
    "$UNPACKED/main/native_modules/build/Release/better_sqlite3.node" \
    "$UNPACKED/main/native_modules/build/Release/pty.node"
do
    missing="$(ldd "$target" 2>/dev/null | grep 'not found' || true)"
    [ -z "$missing" ] || die "Native module has missing shared libraries ($target):\n$missing"
done

info "Application payload verification passed"
