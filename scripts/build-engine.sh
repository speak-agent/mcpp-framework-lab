#!/usr/bin/env bash
# Build mcpp-community/mcpp at MCPP_REF with the released mcpp, and export the
# result as MCPP, the engine every case runs.
#
# Environment: MCPP_REF, MCPP_BOOTSTRAP_BIN. Exports MCPP.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

: "${MCPP_REF:?refs.env names the engine reference}"
: "${MCPP_BOOTSTRAP_BIN:?the step that installs the released mcpp sets it}"
src="$LAB_WORK/mcpp"
rm -rf "$src"
git clone --quiet --depth 1 --branch "$MCPP_REF" https://github.com/mcpp-community/mcpp.git "$src"
sha=$(git -C "$src" rev-parse HEAD)
echo "READING engine: mcpp-community/mcpp $MCPP_REF at $sha"

# The clone's `.xlings.json` pins the mcpp that builds mcpp in that
# repository's own CI. A build inside the checkout obeys it and would install a
# version this job did not choose, so the released mcpp named by MCPP_BOOTSTRAP
# builds the source without it.
rm -f "$src/.xlings.json"

(cd "$src" && "$MCPP_BOOTSTRAP_BIN" build --profile release)

# On Windows the shell opens `bin/mcpp` as `bin/mcpp.exe`, so a glob over both
# names finds one file twice; the plain name is skipped when the `.exe` exists.
built=""
count=0
for f in "$src"/target/*/*/bin/mcpp.exe "$src"/target/*/*/bin/mcpp; do
    [ -f "$f" ] || continue
    case "$f" in *.exe) ;; *) [ -f "$f.exe" ] && continue ;; esac
    built=$f
    count=$((count + 1))
done
if [ "$count" != 1 ]; then
    echo "::error::expected one mcpp binary under target/*/*/bin, found $count"
    find "$src/target" -path '*/bin/*' -type f 2> /dev/null | head -20 || true
    exit 1
fi
version=$("$built" --version | head -1)
echo "READING engine binary: $built"
echo "READING engine version: $version"
printf '%s\n' "$version" > "$LAB_RESULTS/engine-version.txt"
printf 'engine\t%s\t%s\t%s\n' "$MCPP_REF" "$sha" "$version" >> "$LAB_RESULTS/sources.tsv"
export_env MCPP "$built"
