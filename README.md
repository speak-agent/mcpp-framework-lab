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
| `[xlings.overrides]`, `MCPP_XLINGS_OVERRIDE_<NS>_<NAME>` state where a declared payload comes from, and an overridden payload is not provisioned | the build succeeds with `MCPP_NO_AUTO_INSTALL=1`, prints a `Using` line with the matching tag, and records `class: custom` |
| A build program may name its own tool | the build succeeds with `MCPP_NO_AUTO_INSTALL=1`, and the record says the payload was not requested |
| A build whose sources are all the ecosystem's prints what it printed before | the output has no `Using` line and no `custom`, `program` or `host` summary |
| A dependency may not state where a payload comes from | the build is refused, and the message says the dependency states it |
| `--managed-only` refuses a source that is not the ecosystem's | the build is refused and names `xim:cmake` |
| `mcpp why sources`, `why tool`, `why payload`, `--format json` | the answers report the override, and the JSON has kind `mcpp.why.sources` |

## The two branches under test

| Repository | Branch | Pull request | Version |
|---|---|---|---|
| [mcpp-community/mcpp](https://github.com/mcpp-community/mcpp) | `feat/build-sources` | #758 | 2026.10.1.3 |
| [mcpp-community/mcpp-plugins](https://github.com/mcpp-community/mcpp-plugins) | `feat/0.19.0-tool-sources` | #43 | 0.19.0 |

The references are pinned in `refs.env` on the working branch. A released mcpp
(`MCPP_BOOTSTRAP`) builds the engine branch, the built binary runs every case,
and each project depends on the plugins checkout by path.

## Results

No run has been recorded yet.

| Run | Platform | mcpp | Case | Conclusion |
|---|---|---|---|---|

## Re-running

On GitHub, open the Actions tab and run the `lab` workflow, or push to a
branch and open a pull request. Change `refs.env` to test other references.

The workflow runs three jobs, one per platform (`ubuntu-24.04`, `macos-15`,
`windows-2022`). Each installs the released mcpp that `MCPP_BOOTSTRAP` names,
builds the engine at `MCPP_REF`, clones the plugins at `PLUGINS_REF`, and runs
every case as its own step.
