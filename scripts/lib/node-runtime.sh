#!/bin/bash

MANAGED_NODE_VERSION="v22.22.2"
MANAGED_NODE_SHA256_X64="88fd1ce767091fd8d4a99fdb2356e98c819f93f3b1f8663853a2dee9b438068a"

node_is_compatible() {
    local node_path="$1"
    [ -x "$node_path" ] || return 1
    "$node_path" -e '
const [major, minor] = process.versions.node.split(".").map(Number);
process.exit(major > 22 || (major === 22 && minor >= 12) ? 0 : 1);
' >/dev/null 2>&1
}

ensure_managed_node() {
    local destination="$1"
    local source_dir="${ALIBABA_NODE_SOURCE:-}"
    local archive
    local extract_dir
    local extracted

    if node_is_compatible "$destination/bin/node"; then
        export PATH="$destination/bin:$PATH"
        return
    fi

    if [ -n "$source_dir" ] && node_is_compatible "$source_dir/bin/node"; then
        info "Using managed Node.js from $source_dir"
        rm -rf "$destination"
        mkdir -p "$destination"
        cp -a "$source_dir/." "$destination/"
        export PATH="$destination/bin:$PATH"
        return
    fi

    archive="$CACHE_DIR/node/node-${MANAGED_NODE_VERSION}-linux-x64.tar.xz"
    download_file \
        "https://nodejs.org/dist/${MANAGED_NODE_VERSION}/node-${MANAGED_NODE_VERSION}-linux-x64.tar.xz" \
        "$archive"
    verify_sha256 "$archive" "$MANAGED_NODE_SHA256_X64"

    extract_dir="$WORK_DIR/node-extract"
    extracted="$extract_dir/node-${MANAGED_NODE_VERSION}-linux-x64"
    rm -rf "$extract_dir" "$destination"
    mkdir -p "$extract_dir" "$destination"
    tar -xJf "$archive" -C "$extract_dir"
    require_dir "$extracted"
    cp -a "$extracted/." "$destination/"
    node_is_compatible "$destination/bin/node" \
        || die "Downloaded Node.js runtime is not compatible"
    export PATH="$destination/bin:$PATH"
}
