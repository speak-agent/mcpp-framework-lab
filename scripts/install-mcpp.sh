#!/usr/bin/env bash
# Install the released mcpp that MCPP_BOOTSTRAP names, from its GitHub release
# asset, and point it at MCPP_HOME.
#
# Environment: MCPP_BOOTSTRAP, MCPP_HOME. Exports MCPP_BOOTSTRAP_BIN and
# MCPP_VENDORED_XLINGS.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${MCPP_BOOTSTRAP:?refs.env names the released mcpp}"
: "${MCPP_HOME:?the home the cache holds}"
v=$MCPP_BOOTSTRAP

case "$(uname -s)" in
    Linux)                direct="linux-x86_64";  ext="tar.gz"; exe="mcpp" ;;
    Darwin)               direct="macosx-arm64";  ext="tar.gz"; exe="mcpp" ;;
    MINGW*|MSYS*|CYGWIN*) direct="windows-x86_64"; ext="zip";    exe="mcpp.exe" ;;
    *) echo "::error::no release asset for $(uname -s)"; exit 1 ;;
esac
asset="mcpp-${v}-${direct}.${ext}"
url="https://github.com/mcpp-community/mcpp/releases/download/v${v}/${asset}"

dl="$LAB_WORK/bootstrap"
rm -rf "$dl"; mkdir -p "$dl"
echo "fetching $url"
curl -L -fsS --retry 3 --retry-all-errors -o "$dl/$asset" "$url"
case "$ext" in
    zip)    (cd "$dl" && unzip -q "$asset") ;;
    tar.gz) (cd "$dl" && tar -xzf "$asset") ;;
esac
bin="$dl/mcpp-${v}-${direct}/bin/$exe"
[ -f "$bin" ] || { echo "::error::$asset does not hold bin/$exe"; ls -R "$dl" | head -30; exit 1; }

# A released tarball carries its own xlings and finds it there only while the
# tarball is its home. MCPP_HOME is pinned elsewhere, so the first command is
# told where the vendored copy is; mcpp copies it into the pinned home and
# answers from there afterwards. The path is in the host's syntax.
xl="$dl/mcpp-${v}-${direct}/registry/bin/xlings"
[ -f "$xl" ] || xl="$xl.exe"
[ -f "$xl" ] || { echo "::error::no vendored xlings beside the release"; exit 1; }
xl=$(native "$xl")
export MCPP_VENDORED_XLINGS="$xl"

"$bin" --version
"$bin" self config --mirror GLOBAL
export_env MCPP_BOOTSTRAP_BIN "$bin"
export_env MCPP_VENDORED_XLINGS "$xl"
