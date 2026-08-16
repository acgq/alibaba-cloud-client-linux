#!/bin/bash

info() {
    printf '[INFO] %s\n' "$*" >&2
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
}

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

require_file() {
    [ -f "$1" ] || die "Required file not found: $1"
}

require_dir() {
    [ -d "$1" ] || die "Required directory not found: $1"
}

download_file() {
    local url="$1"
    local destination="$2"

    mkdir -p "$(dirname "$destination")"
    if [ -f "$destination" ]; then
        info "Using cached file: $destination"
        return
    fi

    info "Downloading $url"
    if ! curl -L --fail --retry 3 --continue-at - --progress-bar \
        -o "$destination.part" "$url"; then
        rm -f "$destination.part"
        die "Download failed: $url"
    fi
    mv "$destination.part" "$destination"
}

verify_sha256() {
    local file="$1"
    local expected="$2"

    printf '%s  %s\n' "$expected" "$file" | sha256sum -c - >/dev/null \
        || die "SHA256 mismatch: $file"
}

json_value() {
    local file="$1"
    local expression="$2"
    python3 - "$file" "$expression" <<'PY'
import json
import sys

path, expression = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    value = json.load(handle)
for key in expression.split("."):
    value = value[key]
print(value)
PY
}
