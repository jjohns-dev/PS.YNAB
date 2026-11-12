# Contributing Guide

- Minor fixes (typo, doc tweak) can go directly as a pull request.
- Substantive changes should start with a new issue on this repository. See the [ADRs](docs/adr/) for decisions that constrain the module; a change that conflicts with one needs a new ADR that supersedes or amends it.
- **Focus each pull request on a single function or a single cross-cutting concern.**

## Working conventions

- Branch off `main` using `<issue-number>-<short-slug>` (e.g. `3-add-get-ynabplan`).
- Every commit that traces to an issue references it (`refs #N`) in the body. Only the final PR under an umbrella issue uses `closes #N`.
- Do not commit directly to `main`. All changes land through a PR that passes CI. Commits must be signed.
- Commit subjects follow conventional commits (`feat:`, `fix:`, `docs:`, `ci:`), then a blank line and a rationale paragraph explaining *why*.

## New Function Checklist

- Place the file under `Public/` (exported) or `Private/` (internal only), named `Verb-YnabNoun.ps1` to match the function, using an [approved verb](https://learn.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands).
- Follow the cross-cutting rules in [AGENTS.md](AGENTS.md#cross-cutting-rules-every-function-honors): HTTP only through `Invoke-YnabRequest`, amounts converted from milliunits, writes guarded by `SupportsShouldProcess`.
- Include comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.INPUTS`, `.OUTPUTS`, `.EXAMPLE`, `.NOTES`). The `.NOTES` block must include a `Status:` line:

  | Value | Meaning |
  | --- | --- |
  | `Stable` | Production-ready; fully tested and supported |
  | `Beta` | Functional but may have rough edges or limited testing |
  | `Experimental` | Early development; API or behavior may change |
  | `Deprecated` | Still works but will be removed in a future release |

- Add a Pester test at `Tests/Unit/Verb-YnabNoun.tests.ps1`. Mock HTTP so tests are hermetic.
- If the function is exported, add it to `FunctionsToExport` in [`PS.YNAB.psd1`](PS.YNAB.psd1).

## Running the build locally

`Build/build.ps1` is a shim: it reads the `@v2` pin from `.github/workflows/ci.yml`, fetches that version of [`pwsh-module-ci`](https://github.com/jjohns-dev/pwsh-module-ci) into a local cache, and runs its harness against this repo. It needs `git`, PowerShell 7 and network access. Run the same tasks CI runs:

```powershell
./Build/build.ps1 -ResolveDependency -TaskList Init
./Build/build.ps1 -TaskList CombineFunctionsAndStage, Analyze, Test
./Build/build.ps1 -TaskList Cleanup
```

`Staging/` and `Artifacts/` are gitignored. Task names, properties and the expected layout are in the harness's [consumer guide](https://github.com/jjohns-dev/pwsh-module-ci/blob/main/docs/consumer-guide.md).

## Releasing

A release is cut by pushing a `vX.Y.Z` tag. The [release workflow](.github/workflows/release.yml) then builds and tests the tagged commit and publishes a GitHub release with notes generated from the merged PRs' labels and the module zip attached. Nothing is published to the PowerShell Gallery. On pull requests the same workflow runs as a dry run that skips only the publishing step.

1. **Label every PR** with one of the labels in [`.github/release.yml`](.github/release.yml), such as `enhancement`, `bug` or `documentation`, so the release notes group it. Unlabeled PRs fall under "Other Changes"; `ignore-for-release` leaves a PR out.
2. **Set the version first.** `ModuleVersion` in [`PS.YNAB.psd1`](PS.YNAB.psd1) must equal the tag's version. Nothing checks this, and the zip is named from the manifest, so a mismatch ships a release and a zip with different versions. Bump it in a PR and merge that before tagging: major for breaking changes, minor for new functions, patch for fixes.
3. **Tag the merged commit on `main`** with a signed, annotated tag and push it:

   ```powershell
   git tag -s v0.2.0 -m 'v0.2.0' <commit-sha>
   git push origin v0.2.0
   ```

4. **Watch the `release` run** for the tag and confirm the release page lists the notes and the `PS.YNAB-vX.Y.Z.zip` asset.

Never move, delete or reuse a version tag. If a release is wrong, fix forward with a new patch version.
