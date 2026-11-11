# ADR 1: A Dedicated PS.YNAB Module Built on the Shared Harness

## Status

Accepted — 2026-11-10

## Context

- A YNAB API wrapper is wanted, first for a daily spending-anomaly alerter and then for interactive use, including writes.
- The only existing PowerShell Gallery module, `Posh-YNAB`, was last published at 0.2.4 in January 2019, before YNAB moved its documented paths from `/budgets/{budget_id}` to `/plans/{plan_id}` and added write endpoints in 2026.
- The `jjohns-dev` module fleet shares one build harness and its reusable workflows in `pwsh-module-ci`, at `v2`. Repos on it keep only workflow callers, a byte-identical `Build/build.ps1` shim, and an optional `Build/harness.psd1`.
- Fleet repos are public so they can carry repository rulesets and secret scanning on the free plan.
- The fleet names modules `PS.<Name>`; acronym names keep their capitals (`PS.SSL`, `PS.DCU`).
- This repo records its ADR status lines with a date, a deviation from Nygard's format shared with the rest of the fleet.

## Decision

- We will build the wrapper as its own public repository and module, `PS.YNAB`, rather than adopting `Posh-YNAB` or adding functions to an existing fleet module.
- We will consume `pwsh-module-ci`'s `ci.yml`, `release.yml` and `pssa-sarif.yml` pinned `@v2`, with the shared shim as `Build/build.ps1` and no `Build/harness.psd1`.
- We will run CI on `ubuntu-latest` only.
- We will name exported functions `Verb-Ynab<Noun>`.

## Consequences

- **Positive** — build tools, analyzer settings and action pins are maintained once in `pwsh-module-ci`; this repo carries no build code.
- **Positive** — the module can target the current API surface, including plans and write endpoints, without inheriting an unmaintained design.
- **Negative** — every `v2` harness release reaches this repo's CI without review here, and a harness defect breaks this build along with the rest of the fleet.
- **Negative** — a single Linux runner means Windows- or macOS-specific behavior, such as SecretManagement vault differences, is not exercised in CI.
- **Neutral** — the `Ynab` noun prefix casing differs from the module name's `YNAB`, following PowerShell's casing guidance for acronyms longer than two letters.
- **Neutral** — the repo must be added to the fleet's consumer and baseline lists in `pwsh-module-ci` and `.github`, or fleet-wide sweeps will skip it.
