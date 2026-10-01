#!/usr/bin/env python3
"""Print the rows of README's results table for one workflow run.

    python3 scripts/results-table.py RUN_ID [--repo OWNER/NAME]

Downloads the run's `lab-results-*` artifacts with the GitHub CLI and prints one
row per platform and case: run id, platform, mcpp version, the engine commit it
was built from, case, conclusion. The plugins commit is printed above the rows.
"""
import pathlib
import subprocess
import sys
import tempfile

CASES = ["control", "choice-build-mcpp", "override-env", "override-manifest",
         "override-from-dependency", "override-bare-name", "managed-only", "why", "default"]
PLATFORMS = [("Linux", "ubuntu-24.04"), ("macOS", "macos-15"), ("Windows", "windows-2022")]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    run = sys.argv[1]
    repo = []
    if "--repo" in sys.argv:
        repo = ["--repo", sys.argv[sys.argv.index("--repo") + 1]]
    dest = pathlib.Path(tempfile.mkdtemp())
    subprocess.run(["gh", "run", "download", run, "-D", str(dest)] + repo, check=True)
    rows = []
    plugins = set()
    for os_name, runner in PLATFORMS:
        d = dest / ("lab-results-" + os_name)
        version = "not built"
        v = d / "engine-version.txt"
        if v.exists():
            version = v.read_text(encoding="utf-8").strip().replace("mcpp ", "")
        engine = "not built"
        s = d / "sources.tsv"
        if s.exists():
            for line in s.read_text(encoding="utf-8").splitlines():
                f = line.split("\t")
                if f[0] == "engine":
                    engine = f[2][:8]
                if f[0] == "plugins":
                    plugins.add(f[2][:8])
        for case in CASES:
            r = d / (case + ".result")
            conclusion = r.read_text(encoding="utf-8").strip() if r.exists() else "not run"
            rows.append("| %s | %s | %s | %s | %s | %s |" % (run, runner, version, engine, case, conclusion))
    print("plugins commit: " + ", ".join(sorted(plugins)))
    print()
    print("\n".join(rows))


if __name__ == "__main__":
    main()
