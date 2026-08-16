#!/bin/bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

make -s -C "$REPO_DIR" help >/dev/null
grep -q '^pkgver=2.3.3$' "$REPO_DIR/packaging/PKGBUILD"
grep -q '^pkgrel=1$' "$REPO_DIR/packaging/PKGBUILD"
grep -q '^Exec=alibaba-cloud-client %U$' "$REPO_DIR/packaging/alibaba-cloud-client.desktop"
grep -q -- '--no-sandbox' "$REPO_DIR/launcher/start.sh.template"

if grep -Eq '^\s*exec .*--no-sandbox' "$REPO_DIR/launcher/start.sh.template"; then
    echo 'launcher must not disable the Electron sandbox by default' >&2
    exit 1
fi

printf '[TEST] script smoke checks passed\n'
