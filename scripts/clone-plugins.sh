#!/usr/bin/env bash
# Clone mcpp-community/mcpp-plugins at PLUGINS_REF into work/mcpp-plugins, which
# is where every project's dependency by path points.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${PLUGINS_REF:?refs.env names the plugins reference}"
dst="$LAB_WORK/mcpp-plugins"
rm -rf "$dst"
git clone --quiet --depth 1 --branch "$PLUGINS_REF" https://github.com/mcpp-community/mcpp-plugins.git "$dst"
sha=$(git -C "$dst" rev-parse HEAD)
echo "READING plugins: mcpp-community/mcpp-plugins $PLUGINS_REF at $sha"
ver=$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$dst/mcpp.toml" | head -1)
echo "READING plugins version: $ver"
printf 'plugins\t%s\t%s\t%s\n' "$PLUGINS_REF" "$sha" "$ver" >> "$LAB_RESULTS/sources.tsv"
