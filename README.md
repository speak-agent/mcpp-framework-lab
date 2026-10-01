# mcpp-framework-lab

A consumer's-eye validation of one feature that spans two repositories. The
repository holds small mcpp projects and a workflow that builds them on
GitHub-hosted runners with an engine built from source. It contains no
library code.

## What this validates

Every tool a build uses has a source that can be stated, decided by a build
program, and read back. The cases here check that behaviour from the outside,
using only what a consumer can run and read.

| Behaviour | How a case checks it |
|---|---|
| `[xlings.overrides]` and `MCPP_XLINGS_OVERRIDE_<NS>_<NAME>` state where a declared payload comes from, and an overridden payload is not provisioned | the build succeeds with `MCPP_NO_AUTO_INSTALL=1`, prints a `Using` line with the matching tag, and records `class: custom` |
| A build program may name its own tool | the build succeeds with `MCPP_NO_AUTO_INSTALL=1`, and the record says the payload was not requested |
| A build whose sources are all the ecosystem's prints what it printed before | the output has no `Using` line and no `custom`, `program` or `host` summary, and every recorded class is `managed` or `pinned` |
| A dependency may not state where a payload comes from | the build is refused, and the message says the dependency states it |
| `--managed-only` and `MCPP_MANAGED_ONLY=1` refuse a source that is not the ecosystem's | the build is refused and names `xim:cmake` |
| `mcpp why sources`, `why tool`, `why payload`, and `--format json` | the answers report the override, and the JSON has kind `mcpp.why.sources` |
| Every build writes `sources` into `target/<triple>/<fingerprint>/resolution.json` | each case reads that record and asserts on its entries |

## The two branches under test

| Repository | Branch | Pull request | Version |
|---|---|---|---|
| [mcpp-community/mcpp](https://github.com/mcpp-community/mcpp) | `feat/build-sources` | #758 | 2026.10.1.3 |
| [mcpp-community/mcpp-plugins](https://github.com/mcpp-community/mcpp-plugins) | `feat/0.19.0-tool-sources` | #43 | 0.19.0 |

`refs.env` pins the references. A released mcpp (`MCPP_BOOTSTRAP`) builds the
engine branch, the binary it produces runs every case, and each project depends
on the plugins checkout by path.

## Cases

Each case runs in a fresh copy of `projects/`. Every project is a package with a
`build.mcpp` that configures, builds and installs the CMake subproject in
`projects/greet` through the plugins' `deps-cmake` member, links it, and
prints `greet says 42` when run. Each case also runs that program, and checks
the cmake that configured the subproject by reading `CMAKE_COMMAND` from its
`CMakeCache.txt`.

| Case | Project | What it states | Criterion |
|---|---|---|---|
| `control` | `override-env`, no override | nothing | with `MCPP_NO_AUTO_INSTALL=1` the build is refused for want of `xim:cmake` |
| `choice-build-mcpp` | `choice-build-mcpp` | the build program writes `o.cmake = "<host cmake>"` | the build succeeds with `MCPP_NO_AUTO_INSTALL=1`; the output has `Using cmake (mcpp.deps.cmake)` tagged `[program · build.mcpp:<line of o.cmake>]`; `Finished` ends with `· program: cmake (mcpp.deps.cmake)`; `resolution.json` records the payload `xim:cmake` as not requested and the tool as class `program`; the host cmake configured the subproject |
| `override-env` | `override-env` | `MCPP_XLINGS_OVERRIDE_XIM_CMAKE=<host cmake>` | the build succeeds with `MCPP_NO_AUTO_INSTALL=1`; `Using xim:cmake` is tagged `[custom · env MCPP_XLINGS_OVERRIDE_XIM_CMAKE]`; `Finished` ends with `· custom: xim:cmake`; the payload is class `custom` with origin kind `env`; the host cmake configured the subproject |
| `override-manifest` | `override-manifest` | `[xlings.overrides] "xim:cmake" = "<host cmake>"` in `mcpp.toml` | the same, with the tag `[custom · mcpp.toml:<line of the entry>]` and origin kind `manifest` at that line |
| `override-from-dependency` | `override-from-dependency` and `override-plugin` | a local package, used as a dependency, writes `[xlings.overrides]` | the build is refused, and the message says that `override-plugin` states `[xlings.overrides]` and is a dependency of this build |
| `override-bare-name` | `override-manifest` and `override-env` | a program named by a bare word that the shell answers for itself: `{ program = "true" }` in the manifest, `path:true` in the environment | `mcpp why` is not refused with "not found on PATH"; the `Using` line names a path ending in `/true` tagged `[host · mcpp.toml:<line>]`; the JSON has class `host`, the right origin, and an absolute path whose last component is `true`. Skipped on Windows, where the engine asks `where`, which reports programs only |
| `managed-only` | `override-env` | the environment override, with `--managed-only` and then `MCPP_MANAGED_ONLY=1` | both builds are refused and name `xim:cmake`; the same build without the flag succeeds |
| `why` | `override-manifest`, then `override-env` | the manifest override, then the environment override | `why payload cmake` and `why tool cmake` report it; `why sources --format json` has kind `mcpp.why.sources`, status `ok`, the subject `payload:xim:cmake`, class `custom` and the right origin |
| `default` | `default` | nothing | the output has no `Using` line and no `· custom:`, `· program:` or `· host:` on `Finished`; every class in `resolution.json` is `managed` or `pinned`; the payload `xim:cmake` configured the subproject; `--managed-only` accepts the build |

`projects/` holds placeholders that `scripts/lab.sh` replaces in the copy:
`@PLUGINS@` is the plugins checkout and `@CMAKE@` is the cmake found on the
host. A case that needs a host cmake and finds none ends as `skip` with that
reason, and the log says so.

## Why `MCPP_NO_AUTO_INSTALL=1` can be trusted

With `MCPP_NO_AUTO_INSTALL=1` a build that still wants a payload is refused, so
a build that succeeds did not ask for it. That holds only while the payload is
not already installed. Three things keep it true here:

- The workflow saves the cached `MCPP_HOME` before any case runs, after a
  warm-up build that installs the toolchain but not the cmake payload.
- The `default` case runs last, because it is the only one that installs
  `xim:cmake`.
- The `control` case shows, on every run and every platform, that a build which
  states nothing is refused for want of `xim:cmake`.

`MCPP_DEPS_CMAKE_CACHE=off` is set for the whole workflow. `deps-cmake` keeps a
finished installation under a key that names each tool by file name and not by
path, so without it a second case would copy the first case's installation and
run no cmake.

## Results

Pull request run [36884696419](https://github.com/speak-agent/mcpp-framework-lab/actions/runs/36884696419),
which tested the engine at `7819a28c` (`mcpp-community/mcpp`, branch
`feat/build-sources`, built with the released mcpp 2026.10.1.2) and the plugins
at `5d92352b` (`mcpp-community/mcpp-plugins`, branch `feat/0.19.0-tool-sources`,
version 0.19.0). The engine commit is later than `02df8c30`, which carries the
response-file and `which()` changes.

| Run | Platform | mcpp | Engine commit | Case | Conclusion |
|---|---|---|---|---|---|
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | control | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | choice-build-mcpp | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | override-env | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | override-manifest | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | override-from-dependency | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | override-bare-name | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | managed-only | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | why | pass |
| 36884696419 | ubuntu-24.04 | 2026.10.1.3 | 7819a28c | default | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | control | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | choice-build-mcpp | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | override-env | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | override-manifest | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | override-from-dependency | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | override-bare-name | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | managed-only | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | why | pass |
| 36884696419 | macos-15 | 2026.10.1.3 | 7819a28c | default | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | control | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | choice-build-mcpp | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | override-env | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | override-manifest | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | override-from-dependency | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | override-bare-name | skip: a shell builtin is a POSIX notion: the engine finds a name with `where` on Windows, which reports programs only |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | managed-only | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | why | pass |
| 36884696419 | windows-2022 | 2026.10.1.3 | 7819a28c | default | pass |

- No assertion failed, so the run records no finding against the feature.
- One case was skipped. `override-bare-name` is skipped on Windows because a
  shell builtin is a POSIX notion there: the engine finds a name with `where`,
  which reports programs only. The log of that step prints the reason.
- No case was skipped for want of a host cmake: each runner has one
  (`/usr/local/bin/cmake`, `/opt/homebrew/bin/cmake`,
  `C:/Program Files/CMake/bin/cmake.exe`).
- On Windows the default toolchain is `llvm@20.1.7` over the system MSVC
  sysroot, and `resolution.json` records it as `pinned`, so `default` holds
  there as it does elsewhere.
- Run 36879451481 on the first commit of the pull request failed on Windows
  before any case ran. The lab's own `build-engine.sh` counted `mcpp` and
  `mcpp.exe` as two binaries, because Git Bash opens `bin/mcpp` as
  `bin/mcpp.exe`. That is a defect of this repository and was fixed in the next
  commit. The engine built correctly in that run.

## Re-running

On GitHub, run the `lab` workflow from the Actions tab, or push a branch and open
a pull request. Each run clones the engine and plugins references fresh, so a
branch that has moved is tested at its new head; the engine commit of a run is
in its results table.

Change `refs.env` to test other references. The workflow runs one job per
platform (`ubuntu-24.04`, `macos-15`, `windows-2022`). Each job:

1. installs the released mcpp that `MCPP_BOOTSTRAP` names and pins `MCPP_HOME`
   to `.mcpp-home` in the workspace, cached with `actions/cache`;
2. clones the plugins at `PLUGINS_REF` into `work/mcpp-plugins`;
3. builds the engine at `MCPP_REF` with `mcpp build --profile release`, uses the
   binary under `work/mcpp/target/*/*/bin` as `$MCPP`, and fails unless
   `$MCPP --version` prints `mcpp 2026.10.1.3`;
4. warms up the sandbox, saves it to the cache, and runs each case as its own
   step. Every step writes `results/<case>.log` and `results/<case>.result`, and
   the job uploads them as the artifact `lab-results-<OS>`.

To fill the results table from a run:

```
python3 scripts/results-table.py <run-id> --repo speak-agent/mcpp-framework-lab
```

To run a case by hand, export `MCPP` (the engine) and `MCPP_HOME`, run
`scripts/clone-plugins.sh` once, then `bash scripts/lab.sh <case>`. Set
`MCPP_DEPS_CMAKE_CACHE=off`. On a machine whose `MCPP_HOME` already holds the
`xim:cmake` payload the `control` case fails by design, and says so.

## Layout

| Path | Holds |
|---|---|
| `refs.env` | the engine and plugins references and the released mcpp that builds the engine |
| `.github/workflows/lab.yml` | the workflow |
| `projects/` | the consumer projects, the CMake subproject `greet`, and the `override-plugin` package |
| `scripts/install-mcpp.sh`, `clone-plugins.sh`, `build-engine.sh` | the steps before the cases |
| `scripts/lab.sh` | the cases, the warm-up and the summary |
| `scripts/check.py` | the assertions over `resolution.json`, `mcpp why --format json` and `CMakeCache.txt` |
| `scripts/results-table.py` | prints the rows of the results table for a run |
