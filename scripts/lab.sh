#!/usr/bin/env bash
# The cases of the lab: `scripts/lab.sh <case>`, `warmup` or `summary`.
#
# Environment: MCPP (the engine under test), MCPP_HOME. Needs the plugins in
# work/mcpp-plugins (scripts/clone-plugins.sh).
#
# EACH CASE RUNS IN A FRESH COPY of projects/ under work/run/<case>/, with two
# placeholders written in: @PLUGINS@ (the plugins checkout, by path) and
# @CMAKE@ (the host's cmake). A case ends in exactly one of three ways, and the
# script records it in results/<case>.result:
#
#   pass          every assertion held
#   skip: reason  the host cannot run the case; the reason is printed
#   fail: reason  an assertion did not hold; the output that broke it is above
#
# AN ASSERTION IS NEVER RELAXED TO PASS. A case that fails is a finding, and the
# log carries the exact output.
#
# WHY THE CASES THAT SET MCPP_NO_AUTO_INSTALL=1 CAN BE TRUSTED. With that
# variable a build that still wants a payload is refused, so a build that
# succeeds did not ask for it. That holds only while the payload is not already
# installed, so the `control` case first shows that a build stating nothing is
# refused for want of xim:cmake on this runner. The workflow saves the cached
# MCPP_HOME before any case runs and runs `timing` and `default` last, so a
# payload that either installs reaches no other case and no later run.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

CASES="control choice-build-mcpp override-env override-manifest override-from-dependency override-bare-name managed-only why timing default"

# ── helpers ────────────────────────────────────────────────────────────────

# The assertions over resolution.json and the JSON of `mcpp why`, run by
# whichever python3 this host has.
check() {
    local py
    py=$(python_cmd) || { echo "no python3 on this host"; return 1; }
    "$py" "$(native "$LAB_ROOT/scripts/check.py")" "$@"
}

out=""
rc=0
P=""
CMAKE=""

# `cmake` on this host, in the host's path syntax, or nothing.
find_cmake() {
    local c
    c=$(command -v cmake 2> /dev/null || true)
    [ -n "$c" ] || return 1
    if [ -f "$c.exe" ]; then c="$c.exe"; fi
    native "$c"
}

# stage CASE: a fresh copy of projects/ with the placeholders replaced. Sets P.
stage() {
    local dir="$LAB_WORK/run/$1" plugins f
    rm -rf "$dir"
    mkdir -p "$dir"
    cp -R "$LAB_ROOT/projects" "$dir/projects"
    P="$dir/projects"
    plugins=$(native "$LAB_WORK/mcpp-plugins")
    [ -f "$LAB_WORK/mcpp-plugins/mcpp.toml" ] || { echo "no plugins checkout at $LAB_WORK/mcpp-plugins"; exit 1; }
    find "$P" -type f \( -name mcpp.toml -o -name build.mcpp \) | while read -r f; do
        sed -e "s|@PLUGINS@|$plugins|g" -e "s|@CMAKE@|$CMAKE|g" "$f" > "$f.tmp"
        mv "$f.tmp" "$f"
    done
}

# mcpp_run [NAME=value ...] -- ARGS...: run the engine in the current
# directory, print the command and its whole output, and keep both: the output
# in $out (carriage returns removed) and the exit status in $rc.
mcpp_run() {
    local envs=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
    shift
    echo "+ ${envs[*]-} mcpp $*"
    set +e
    out=$(env NO_COLOR=1 ${envs[@]+"${envs[@]}"} "$MCPP" "$@" 2>&1)
    rc=$?
    set -e
    out=${out//$'\r'/}
    printf '%s\n' "$out"
    echo "+ exit status $rc"
}

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# The lines of $out that begin with `Using`, which is how a build reports a
# source that is not the ecosystem's, and the lines that begin with `Finished`.
using_lines()    { printf '%s\n' "$out" | grep -E '^[[:space:]]*Using ' || true; }
finished_lines() { printf '%s\n' "$out" | grep -E '^[[:space:]]*Finished ' || true; }

CASE=""
record_result() { printf '%s\n' "$1" > "$LAB_RESULTS/$CASE.result"; }
pass() { record_result "pass"; echo "RESULT $CASE: pass"; exit 0; }
skip() { record_result "skip: $1"; echo "RESULT $CASE: skip: $1"; echo "::notice title=skipped $CASE::$1"; exit 0; }
fail() { record_result "fail: $1"; echo "RESULT $CASE: fail: $1"; echo "::error title=$CASE::$1"; exit 1; }

need_cmake() {
    CMAKE=$(find_cmake) || skip "no cmake on this host, so there is no tool to name"
    echo "READING host cmake: $CMAKE"
}

# the line of FILE that matches a fixed-prefix regex, as a number
line_of() { grep -n -E "$1" "$2" | head -1 | cut -d: -f1; }

# ── the cases ──────────────────────────────────────────────────────────────

# The premise of every case that sets MCPP_NO_AUTO_INSTALL=1. A project that
# states nothing needs xim:cmake: its build program asks for it. With the
# payload absent and the installer forbidden, the build must be refused, naming
# it. A build that succeeds here would mean the payload is already on this
# runner, and "built under MCPP_NO_AUTO_INSTALL=1" would then prove nothing.
case_control() {
    stage control
    local store="$MCPP_HOME/registry/data/xpkgs"
    echo "READING payload store: $(ls -d "$store"/xim-x-cmake* 2> /dev/null || echo 'xim-x-cmake is not installed')"
    cd "$P/override-env"
    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- build
    [ "$rc" -ne 0 ] || fail "a build that states no tool was not refused under MCPP_NO_AUTO_INSTALL=1, so xim:cmake is already installed on this runner and the cases below prove less"
    contains "$out" "xim:cmake" || fail "the refusal does not name xim:cmake"
    contains "$out" "Finished" && fail "the build finished although it was refused"
    pass
}

case_choice_build_mcpp() {
    need_cmake
    stage choice-build-mcpp
    cd "$P/choice-build-mcpp"
    local line; line=$(line_of '^ +o\.cmake +=' build.mcpp)
    [ -n "$line" ] || fail "the project does not assign o.cmake"
    echo "READING o.cmake is assigned on line $line of build.mcpp"

    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- build
    [ "$rc" -eq 0 ] || fail "the build with a named cmake did not succeed under MCPP_NO_AUTO_INSTALL=1"
    local u; u=$(using_lines | grep 'Using cmake (mcpp.deps.cmake)' || true)
    [ -n "$u" ] || fail "no 'Using cmake (mcpp.deps.cmake)' line"
    contains "$u" "[program · build.mcpp:" || fail "the Using line's tag is not [program · build.mcpp:<line>]: $u"
    contains "$u" "[program · build.mcpp:$line]" || fail "the tag names another line than $line: $u"
    contains "$(finished_lines)" "· program: cmake (mcpp.deps.cmake)" \
        || fail "the Finished line does not summarise the program source: $(finished_lines)"
    check record \
        --entry payload:xim:cmake --considered "not requested by this build" \
        --entry tool:mcpp.deps.cmake:cmake --class program --origin-kind build-program --origin-line "$line" \
        || fail "resolution.json does not say that the payload was not requested and the program chose the tool"

    check ran-cmake --same-as "$CMAKE" || fail "the cmake that configured the subproject is not the one the build program named"

    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- run
    [ "$rc" -eq 0 ] && contains "$out" "greet says 42" || fail "the library the named cmake built does not run"
    pass
}

# override_case NAME ORIGIN_KIND TAG [ENV...]: the shared body of the two cases
# that state the override, one through the environment and one through the
# manifest.
override_checks() {
    local tag=$1 kind=$2 line=$3
    shift 3
    mcpp_run MCPP_NO_AUTO_INSTALL=1 "$@" -- build
    [ "$rc" -eq 0 ] || fail "the build with an overridden xim:cmake did not succeed under MCPP_NO_AUTO_INSTALL=1"
    local u; u=$(using_lines | grep 'Using xim:cmake' || true)
    [ -n "$u" ] || fail "no 'Using xim:cmake' line"
    contains "$u" "$tag" || fail "the Using line's tag is not $tag: $u"
    contains "$(finished_lines)" "· custom: xim:cmake" \
        || fail "the Finished line does not summarise the custom source: $(finished_lines)"
    if [ -n "$line" ]; then
        check record --entry payload:xim:cmake --class custom --origin-kind "$kind" --origin-line "$line" \
            || fail "resolution.json does not record class custom from $kind at line $line"
    else
        check record --entry payload:xim:cmake --class custom --origin-kind "$kind" \
            || fail "resolution.json does not record class custom from $kind"
    fi
    check ran-cmake --same-as "$CMAKE" || fail "the cmake that configured the subproject is not the one the override states"

    mcpp_run MCPP_NO_AUTO_INSTALL=1 "$@" -- run
    [ "$rc" -eq 0 ] && contains "$out" "greet says 42" || fail "the library the overriding cmake built does not run"
}

case_override_env() {
    need_cmake
    stage override-env
    cd "$P/override-env"
    override_checks "[custom · env MCPP_XLINGS_OVERRIDE_XIM_CMAKE]" env "" "MCPP_XLINGS_OVERRIDE_XIM_CMAKE=$CMAKE"
    pass
}

case_override_manifest() {
    need_cmake
    stage override-manifest
    cd "$P/override-manifest"
    local line; line=$(line_of '^"xim:cmake" *=' mcpp.toml)
    [ -n "$line" ] || fail "the manifest does not state xim:cmake"
    echo "READING the override is stated on line $line of mcpp.toml"
    override_checks "[custom · mcpp.toml:$line]" manifest "$line"
    pass
}

case_override_from_dependency() {
    need_cmake
    stage override-from-dependency
    cd "$P/override-from-dependency"
    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- build
    [ "$rc" -ne 0 ] || fail "a build whose dependency writes [xlings.overrides] was not refused"
    contains "$out" "\`override-plugin\` states [xlings.overrides]" \
        || fail "the refusal does not say that the dependency override-plugin states [xlings.overrides]"
    contains "$out" "it is a dependency of this build" \
        || fail "the refusal does not say that the package is a dependency of this build"
    contains "$out" "Finished" && fail "the build finished although a dependency stated an override"
    pass
}

# A bare name that is also a shell builtin. `command -v true` prints `true`, not
# a path, because the shell answers with what it would run. An override that
# names such a program by its bare name must still be found on PATH. Only
# the resolution is asserted, through `mcpp why`: nothing here builds, and a
# `true` that stands in for cmake would configure nothing.
case_override_bare_name() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) skip "a shell builtin is a POSIX notion: the engine finds a name with \`where\` on Windows, which reports programs only" ;;
    esac
    if [ ! -x /usr/bin/true ] && [ ! -x /bin/true ]; then skip "this host has no \`true\` program to find"; fi
    need_cmake
    stage override-bare-name
    local json="$LAB_WORK/run/override-bare-name/sources.json" err="$LAB_WORK/run/override-bare-name/sources.err"
    echo "READING the shell answers: $(sh -c 'command -v true')"

    # the manifest says `{ program = "true" }`
    cd "$P/override-manifest"
    sed -e 's|^"xim:cmake" *=.*|"xim:cmake" = { program = "true" }|' mcpp.toml > mcpp.toml.new
    mv mcpp.toml.new mcpp.toml
    local line; line=$(line_of '^"xim:cmake" *=' mcpp.toml)
    [ -n "$line" ] || fail "the manifest does not state xim:cmake"
    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- why payload cmake
    [ "$rc" -eq 0 ] || fail "an override naming the bare word true was refused"
    contains "$out" "is not found on PATH" && fail "the refusal says true is not found on PATH although this host has /usr/bin/true"
    local u; u=$(printf '%s\n' "$out" | grep -E 'Using xim:cmake' || true)
    [ -n "$u" ] || fail "no 'Using xim:cmake' line"
    case "$u" in
        *"/true  [host · mcpp.toml:$line]"*) ;;
        *) fail "the Using line does not name a path ending in /true with the tag [host · mcpp.toml:$line]: $u" ;;
    esac
    echo "+ mcpp why sources --format json"
    set +e
    MCPP_NO_AUTO_INSTALL=1 NO_COLOR=1 "$MCPP" why sources --format json > "$json" 2> "$err"
    rc=$?
    set -e
    echo "+ exit status $rc; standard error:"; cat "$err"
    [ "$rc" -eq 0 ] || fail "mcpp why sources --format json failed for a bare-name override"
    check why "$(native "$json")" \
        --entry payload:xim:cmake --class host --origin-kind manifest --origin-line "$line" --value-basename true \
        || fail "the JSON of why sources does not report a host program named true"

    # the environment says `path:true`
    cd "$P/override-env"
    echo "+ mcpp why sources --format json (MCPP_XLINGS_OVERRIDE_XIM_CMAKE=path:true)"
    set +e
    MCPP_NO_AUTO_INSTALL=1 MCPP_XLINGS_OVERRIDE_XIM_CMAKE=path:true NO_COLOR=1 "$MCPP" why sources --format json > "$json" 2> "$err"
    rc=$?
    set -e
    echo "+ exit status $rc; standard error:"; cat "$err"
    [ "$rc" -eq 0 ] || fail "mcpp why sources --format json failed for MCPP_XLINGS_OVERRIDE_XIM_CMAKE=path:true"
    check why "$(native "$json")" \
        --entry payload:xim:cmake --class host --origin-kind env --value-basename true \
        || fail "the JSON of why sources does not report a host program named true for the environment override"
    pass
}

case_managed_only() {
    need_cmake
    stage managed-only
    cd "$P/override-env"
    local over="MCPP_XLINGS_OVERRIDE_XIM_CMAKE=$CMAKE"

    mcpp_run MCPP_NO_AUTO_INSTALL=1 "$over" -- build --managed-only
    [ "$rc" -ne 0 ] || fail "--managed-only did not refuse an overridden xim:cmake"
    contains "$out" "managed-only" || fail "the refusal does not name --managed-only"
    contains "$out" "xim:cmake" || fail "the refusal does not name xim:cmake"
    contains "$out" "Finished" && fail "the build finished under --managed-only"

    # the same refusal through the environment
    rm -rf target
    mcpp_run MCPP_NO_AUTO_INSTALL=1 MCPP_MANAGED_ONLY=1 "$over" -- build
    [ "$rc" -ne 0 ] || fail "MCPP_MANAGED_ONLY=1 did not refuse an overridden xim:cmake"
    contains "$out" "xim:cmake" || fail "the refusal under MCPP_MANAGED_ONLY=1 does not name xim:cmake"

    # and the control: without the flag the same build succeeds
    rm -rf target
    mcpp_run MCPP_NO_AUTO_INSTALL=1 "$over" -- build
    [ "$rc" -eq 0 ] || fail "the same build without --managed-only did not succeed, so the refusals above prove nothing"
    pass
}

case_why() {
    need_cmake
    stage why
    cd "$P/override-manifest"
    local line; line=$(line_of '^"xim:cmake" *=' mcpp.toml)
    [ -n "$line" ] || fail "the manifest does not state xim:cmake"
    local json="$LAB_WORK/run/why/sources.json" err="$LAB_WORK/run/why/sources.err"

    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- why payload cmake
    [ "$rc" -eq 0 ] || fail "mcpp why payload cmake failed"
    contains "$out" "payload:xim:cmake" || fail "why payload cmake does not list payload:xim:cmake"
    contains "$out" "custom · mcpp.toml:$line" || fail "why payload cmake does not give the origin custom · mcpp.toml:$line"

    mcpp_run MCPP_NO_AUTO_INSTALL=1 -- why tool cmake
    [ "$rc" -eq 0 ] || fail "mcpp why tool cmake failed"
    contains "$out" "tool:mcpp.deps.cmake:cmake" || fail "why tool cmake does not list tool:mcpp.deps.cmake:cmake"
    contains "$out" "custom · mcpp.toml:$line" || fail "why tool cmake does not give the origin custom · mcpp.toml:$line"

    echo "+ mcpp why sources --format json"
    set +e
    MCPP_NO_AUTO_INSTALL=1 NO_COLOR=1 "$MCPP" why sources --format json > "$json" 2> "$err"
    rc=$?
    set -e
    echo "+ exit status $rc; standard error:"; cat "$err"
    [ "$rc" -eq 0 ] || fail "mcpp why sources --format json failed"
    check why "$(native "$json")" \
        --entry payload:xim:cmake --class custom --origin-kind manifest --origin-line "$line" --origin-key "[xlings.overrides]" \
        --entry tool:mcpp.deps.cmake:cmake --class custom --origin-kind manifest --origin-line "$line" \
        || fail "the JSON of why sources does not report the manifest override"

    # the override stated through the environment reads back as such
    cd "$P/override-env"
    echo "+ mcpp why sources --format json (override through the environment)"
    set +e
    MCPP_NO_AUTO_INSTALL=1 MCPP_XLINGS_OVERRIDE_XIM_CMAKE="$CMAKE" NO_COLOR=1 "$MCPP" why sources --format json > "$json" 2> "$err"
    rc=$?
    set -e
    echo "+ exit status $rc; standard error:"; cat "$err"
    [ "$rc" -eq 0 ] || fail "mcpp why sources --format json failed with an environment override"
    check why "$(native "$json")" \
        --entry payload:xim:cmake --class custom --origin-kind env \
        || fail "the JSON of why sources does not report the environment override"
    pass
}

# How much a build saves by naming the host's cmake instead of installing the
# xim:cmake payload. Three whole `mcpp build`s, each from a clean state (the
# project's target/ removed):
#
#   named before          the build program names the host cmake
#   control               nothing names cmake, so the member asks for the payload
#   named after           the named build again
#   control, installed    the control again, now that the payload is installed
#
# The named build runs on both sides of the control so that the order of the
# builds is visible in the numbers instead of hiding in them. The last build
# separates what installing the payload costs from what the control project
# costs: the control with the payload already installed provisions nothing. This case runs
# after every case that needs the payload to be absent, and before `default`.
#
# THE MEASUREMENT IS COLD OR IT IS LABELLED WARM. It is cold when the payload
# was not installed before the control and the control's own output has the
# `Downloading xim:cmake` line. A control that downloaded nothing is reported as
# warm, with the reason, and is not a measurement of the download.
now() {
    local py; py=$(python_cmd) || { echo 0; return; }
    "$py" -c 'import time; print("%.3f" % time.time())'
}
elapsed() { awk -v a="$2" -v b="$1" 'BEGIN { printf "%.1f", a - b }'; }

case_timing() {
    need_cmake
    stage timing
    local store="$MCPP_HOME/registry/data/xpkgs/xim-x-cmake"
    local before="cold"
    if [ -n "$(ls "$store" 2> /dev/null | head -1)" ]; then before="warm: xim:cmake was installed before the control ran"; fi
    echo "READING payload store before the control: $(ls -d "$store"/* 2> /dev/null || echo 'xim-x-cmake is not installed')"
    echo "READING host cmake: $("$CMAKE" --version | head -1)"
    echo "READING runner image: ${ImageOS:-unknown} ${ImageVersion:-unknown}"

    local named_dir="$P/choice-build-mcpp" control_dir="$P/default"
    local t0 t1 named_before control named_after

    cd "$named_dir"; rm -rf target
    echo "== named, before the control"
    t0=$(now); mcpp_run -- build; t1=$(now); named_before=$(elapsed "$t0" "$t1")
    [ "$rc" -eq 0 ] || fail "the build that names the host cmake did not succeed"
    contains "$out" "Downloading xim:" && fail "the build that names the host cmake downloaded a payload"
    contains "$(using_lines)" "Using cmake (mcpp.deps.cmake)" || fail "the named build reports no Using line for cmake"

    cd "$control_dir"; rm -rf target
    echo "== control: nothing names cmake"
    t0=$(now); mcpp_run -- build; t1=$(now); control=$(elapsed "$t0" "$t1")
    [ "$rc" -eq 0 ] || fail "the control build did not succeed"
    [ -z "$(using_lines)" ] || fail "the control build printed a Using line: $(using_lines)"
    printf '%s\n' "$out" > "$LAB_WORK/run/timing/control.out"
    local dl; dl=$(check downloads "$(native "$LAB_WORK/run/timing/control.out")")
    echo "$dl"
    local n all_mb all_s cmake_version cmake_mb cmake_s
    n=$(printf '%s\n' "$dl" | sed -n 's/^n=//p')
    all_mb=$(printf '%s\n' "$dl" | sed -n 's/^all_mb=//p')
    all_s=$(printf '%s\n' "$dl" | sed -n 's/^all_s=//p')
    cmake_version=$(printf '%s\n' "$dl" | sed -n 's/^cmake_version=//p')
    cmake_mb=$(printf '%s\n' "$dl" | sed -n 's/^cmake_mb=//p')
    cmake_s=$(printf '%s\n' "$dl" | sed -n 's/^cmake_s=//p')
    if [ -z "$cmake_version" ]; then
        if [ "$before" = "cold" ]; then before="warm: the control's output has no Downloading xim:cmake line"; fi
    fi
    local installed_mb; installed_mb=$(du -sk "$store" 2> /dev/null | awk '{ printf "%.0f", $1 / 1024 }' || true)

    cd "$named_dir"; rm -rf target
    echo "== named, after the control"
    t0=$(now); mcpp_run -- build; t1=$(now); named_after=$(elapsed "$t0" "$t1")
    [ "$rc" -eq 0 ] || fail "the second build that names the host cmake did not succeed"
    contains "$out" "Downloading xim:" && fail "the second build that names the host cmake downloaded a payload"

    cd "$control_dir"; rm -rf target
    echo "== control again, with the payload installed"
    t0=$(now); mcpp_run -- build; t1=$(now); local control_installed; control_installed=$(elapsed "$t0" "$t1")
    [ "$rc" -eq 0 ] || fail "the control build with the payload installed did not succeed"
    contains "$out" "Downloading xim:" && fail "the control build downloaded a payload although it was installed"

    local named; named=$(awk -v a="$named_before" -v b="$named_after" 'BEGIN { printf "%.1f", (a + b) / 2 }')
    local saved; saved=$(awk -v c="$control" -v n="$named" 'BEGIN { printf "%.1f", c - n }')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${LAB_PLATFORM:-$(uname -s)}" "${ImageOS:-unknown} ${ImageVersion:-unknown}" \
        "$("$CMAKE" --version | head -1 | sed 's/cmake version //')" "${cmake_version:-none}" "$before" \
        "$control" "$named_before" "$named_after" "$saved" \
        "${cmake_mb:-0}" "${cmake_s:-0}" "$all_mb" "$all_s" "${installed_mb:-0}" "$control_installed" > "$LAB_RESULTS/timing.tsv"
    echo "TIMING state: $before"
    echo "TIMING control ${control}s; named ${named_before}s before and ${named_after}s after (mean ${named}s); the control took ${saved}s longer"
    echo "TIMING control with the payload installed ${control_installed}s"
    echo "TIMING xim:cmake download: ${cmake_mb:-none} MB in ${cmake_s:-none}s; all $n payloads of the control: ${all_mb} MB in ${all_s}s; installed size ${installed_mb:-?} MB"
    pass
}

# Nothing is stated: every source is the ecosystem's, and xim:cmake is installed
# on request. `timing` also installs the payload, so both run last.
case_default() {
    stage default
    cd "$P/default"
    mcpp_run -- build
    [ "$rc" -eq 0 ] || fail "the default build did not succeed"
    [ -z "$(using_lines)" ] || fail "the default build printed a Using line: $(using_lines)"
    [ -n "$(finished_lines)" ] || fail "the default build printed no Finished line"
    local f; f=$(finished_lines)
    for t in "· custom:" "· program:" "· host:"; do
        contains "$f" "$t" && fail "the Finished line of the default build carries '$t': $f"
    done
    check record --only-classes managed,pinned \
        || fail "resolution.json holds a source that is not managed or pinned, or holds none"

    check ran-cmake --under "$MCPP_HOME/registry/data/xpkgs/xim-x-cmake" \
        || fail "the cmake that configured the subproject is not the xim:cmake payload"

    mcpp_run -- run
    [ "$rc" -eq 0 ] && contains "$out" "greet says 42" || fail "the default build's program does not run"

    # a build whose sources are all the ecosystem's is accepted by --managed-only
    mcpp_run -- build --managed-only
    [ "$rc" -eq 0 ] || fail "--managed-only refused a build whose sources are all the ecosystem's"
    pass
}

# Not a case. Builds one project that names the host's cmake without
# MCPP_NO_AUTO_INSTALL, so that everything the cases need except the cmake
# payload (the toolchain, the host modules' build) is installed before the
# workflow saves MCPP_HOME. A missing cmake is not an error here: the cases that
# need one skip with their own reason.
warmup() {
    CASE=warmup
    CMAKE=$(find_cmake) || { echo "no host cmake: nothing to warm up"; exit 0; }
    stage warmup
    cd "$P/choice-build-mcpp"
    mcpp_run -- build
    [ "$rc" -eq 0 ] || { echo "::warning::the warm-up build failed; the cases run anyway"; exit 1; }
}

summary() {
    local md="$LAB_RESULTS/summary.md" c r
    {
        echo "### Lab results"
        echo
        echo "- engine: $(cat "$LAB_RESULTS/engine-version.txt" 2> /dev/null || echo 'not built')"
        echo "- platform: ${LAB_PLATFORM:-$(uname -s)}"
        echo
        echo "| Case | Conclusion |"
        echo "|---|---|"
        for c in $CASES; do
            r=$(cat "$LAB_RESULTS/$c.result" 2> /dev/null || echo 'not run')
            echo "| $c | $r |"
        done
    } > "$md"
    if [ -f "$LAB_RESULTS/timing.tsv" ]; then
        awk -F'\t' '{
            print ""
            print "Timing (" $5 "): control " $6 " s, named " $7 " s before and " $8 " s after, difference " $9 " s, control with the payload installed " $15 " s;"
            print "xim:cmake " $4 ", " $10 " MB downloaded in " $11 " s, " $14 " MB installed."
        }' "$LAB_RESULTS/timing.tsv" >> "$md"
    fi
    cat "$md"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat "$md" >> "$GITHUB_STEP_SUMMARY"; fi
}

# ── dispatch ───────────────────────────────────────────────────────────────

cmd=${1:-}
case "$cmd" in
    summary) summary; exit 0 ;;
    warmup)
        : "${MCPP:?the engine under test}"
        : "${MCPP_HOME:?the sandbox the engine uses}"
        ( warmup ) 2>&1 | tee "$LAB_RESULTS/warmup.log"; exit "${PIPESTATUS[0]}" ;;
    control|choice-build-mcpp|override-env|override-manifest|override-from-dependency|override-bare-name|managed-only|why|timing|default)
        : "${MCPP:?the engine under test}"
        : "${MCPP_HOME:?the sandbox the engine uses}"
        CASE=$cmd
        fn="case_$(printf '%s' "$cmd" | tr '-' '_')"
        rm -f "$LAB_RESULTS/$CASE.result"
        set +e
        ( set -euo pipefail; "$fn" ) 2>&1 | tee "$LAB_RESULTS/$CASE.log"
        status=${PIPESTATUS[0]}
        set -e
        # The record the case left, kept with its log as the evidence.
        rec=$(find "$LAB_WORK/run/$CASE" -name resolution.json 2> /dev/null | head -1 || true)
        if [ -n "$rec" ]; then cp "$rec" "$LAB_RESULTS/$CASE.resolution.json"; fi
        if [ ! -f "$LAB_RESULTS/$CASE.result" ]; then
            record_result "fail: the case ended with exit status $status before it reached a conclusion"
            echo "RESULT $CASE: fail: exit status $status without a conclusion"
            exit 1
        fi
        exit "$status"
        ;;
    *) echo "usage: $0 $(printf '%s' "$CASES" | tr ' ' '|')|warmup|summary"; exit 2 ;;
esac
