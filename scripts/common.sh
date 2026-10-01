# Shared by the scripts. Source it; it runs nothing.
#
# Written for bash 3.2 as well as 5, because the macOS runner's bash may be the
# older one, and for Git Bash on Windows, where paths have two spellings.

LAB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LAB_WORK=${LAB_WORK:-$LAB_ROOT/work}
LAB_RESULTS=${LAB_RESULTS:-$LAB_ROOT/results}
mkdir -p "$LAB_WORK" "$LAB_RESULTS"

# A path in the host's own syntax. mcpp and xlings are native programs, and on
# Windows they read `D:/a/x`, not Git Bash's `/d/a/x`. Elsewhere the path is
# returned as it is.
native() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# Make a variable visible to this script and to the steps that follow it.
export_env() {
    export "$1=$2"
    if [ -n "${GITHUB_ENV:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; fi
}

# The command that runs Python 3, or fail. `python3` on a Windows runner can be
# the Microsoft Store stub, which exists and does nothing, so each candidate is
# asked to run a statement before it is chosen.
python_cmd() {
    local c
    for c in python3 python; do
        if command -v "$c" > /dev/null 2>&1 \
            && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' > /dev/null 2>&1; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# Python reads and writes UTF-8 whatever the console's code page is: mcpp's
# source lines contain U+00B7 and U+2190.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8
