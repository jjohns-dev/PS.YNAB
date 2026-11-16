# AGENTS.md — repo conventions for `PS.YNAB`

Context for an AI agent (or a human working alongside one) working in this repo.

**Read first:** [`docs/design.md`](docs/design.md) for the module's purpose, the design rules every function follows, the auth model and the YNAB API facts it relies on. It also maps where each kind of fact lives: decisions in [`docs/adr/`](docs/adr/), per-step specs in [`docs/specs/`](docs/specs/), and the plan and open questions in tracking issue [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1).

Keep each fact in its authoritative place and link to it from elsewhere; don't restate it.

## Layout

```text
PS.YNAB/
  .devcontainer/         devcontainer + Dockerfile
  .github/
    workflows/           callers of the shared pwsh-module-ci workflows (@v2)
    release.yml          release-notes categorization config
    dependabot.yml
    CODEOWNERS
  .vscode/               editor settings + PSScriptAnalyzer rules
  Build/build.ps1        shim that runs the shared harness; do not edit
  Public/                one .ps1 per exported function, Verb-YnabNoun.ps1
  Private/               internal helpers, NOT exported
  Tests/Unit/            Pester tests, <Function>.tests.ps1
  docs/adr/              architectural decision records
  PS.YNAB.psd1           module manifest (authoritative export list)
  PS.YNAB.psm1           module loader (dot-sources Public/ + Private/)
```

## Build and CI

The build is the shared harness in [`pwsh-module-ci`](https://github.com/jjohns-dev/pwsh-module-ci), pinned `@v2` in all three workflow callers. Its [consumer guide](https://github.com/jjohns-dev/pwsh-module-ci/blob/main/docs/consumer-guide.md) is authoritative for the layout the harness expects, test selection, dependency resolution and local runs.

- `Build/build.ps1` is a byte-identical copy of that repo's `templates/Build/build.ps1`. Do not edit it; replace it with the template if the harness warns about drift.
- Runtime module dependencies go in the manifest's `RequiredModules`. The harness installs each at its latest release unless the entry carries `RequiredVersion`.
- There is no `Build/harness.psd1`. Add one only for a setting the consumer guide lists.
- CI runs on `ubuntu-latest` only. The required check is `validate / validate (ubuntu-latest)`; adding a runner means adding its check to the `protect` ruleset.
- The `validate` job sets a `min-tests` floor in `.github/workflows/ci.yml`. Derive it as `executed - min(floor(executed * 0.05), 10)`, where `executed` is the JUnit root's `tests` minus `disabled`, read from the run's `Pester Results` artifact and never predicted (pwsh-module-ci `docs/test-integrity.md`, ADR-0004). Every PR that adds tests raises the floor, and a PR that deletes tests re-derives it. Record the executed count and the arithmetic in the trailing comment.

## Working conventions

- Branch off `main` using `<issue-number>-<short-slug>`; no direct commits to `main`.
- One PR per function or per cross-cutting concern.
- Every function ships with comment-based help (`.SYNOPSIS`/`.DESCRIPTION`/`.PARAMETER`/`.INPUTS`/`.OUTPUTS`/`.EXAMPLE`/`.NOTES`), a `.NOTES Status:` line, and a `Tests/Unit/<Verb-Noun>.tests.ps1`. Exports are added to `FunctionsToExport`.
- Tests mock `Invoke-YnabRequest` (or `Invoke-RestMethod` inside its own tests) so they never reach the network.
