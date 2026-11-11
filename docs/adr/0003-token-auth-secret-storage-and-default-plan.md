# ADR 3: Token Auth, Secret Storage and the Default Plan

## Status

Proposed — 2026-11-10

## Context

- YNAB offers two auth schemes: a personal access token (full read/write, no scopes, no expiry) and an OAuth authorization code grant (`read-only` scope, access tokens that expire 2 hours after they are granted, refresh tokens).
- Interactive use needs only the personal token. Where the unattended alerter will run, and so how it would reach its secrets, is undecided.
- Two OAuth details are unverified: which redirect URIs an OAuth app accepts, and whether every refresh issues a new refresh token.
- The repo's cross-cutting rules make `Invoke-YnabRequest` the only HTTP caller and the owner of the auth header and OAuth refresh.
- SecretManagement 1.1.2 writes to the default vault when no `-Vault` is given, and reads by searching the default vault first, then every other registered vault.
- SecretStore 1.0.6 supports only `CurrentUser` scope, so all of one user's secrets share one store. It defaults to password authentication with a 900-second timeout; with `-Interaction None`, a locked store throws `PasswordRequiredException` instead of prompting.
- Most endpoints take a `plan_id`; the API accepts `last-used` without the caller knowing an ID. The docs do not define what "used" means.
- The maintainer already sets per-session defaults for other modules with `$PSDefaultParameterValues` in a pwsh profile.
- Observed on pwsh 7: a `$PSDefaultParameterValues` entry binds on calls made from the session, but not on calls one module function makes to another.
- CI runs on `ubuntu-latest` with no vault registered (ADR-0001).

## Decision

- We will support personal-token auth only until the OAuth step in the plan.
- We will have `Invoke-YnabRequest` get its `Authorization` value from one private resolver. OAuth will be added by changing that resolver, and an auth-mode setting will be introduced only then.
- We will store the token as a secret named `YnabToken` through SecretManagement, without naming a vault, behind private `Get-YnabSecret` / `Save-YnabSecret` wrappers, and add `Microsoft.PowerShell.SecretManagement` to `RequiredModules`.
- We will never register, configure or unlock a vault from the module. A locked vault surfaces as an error or a prompt to the caller.
- We will default every `-PlanId` parameter to `'last-used'`, keep no module-level default-plan state, and document `$PSDefaultParameterValues['*-Ynab*:PlanId']` as the per-session override.
- We will have module functions pass `-PlanId` explicitly to any module function they call.
- We will defer OAuth, the scheduled job's host, and its unattended secret access to their steps in the plan.

## Consequences

- **Positive** — no auth code is written for an OAuth flow with unverified details, and adding OAuth later touches only the resolver.
- **Positive** — the module works with any SecretManagement vault and carries no vault configuration of its own.
- **Positive** — the default plan needs no module code, and a user with one plan needs no setup at all.
- **Negative** — a misspelled `$PSDefaultParameterValues` key or parameter name is ignored silently, so calls fall back to `last-used`, which may be a different plan.
- **Negative** — because `last-used` is undefined in the docs, unattended consumers such as the alerter must pass an explicit `-PlanId` rather than rely on the default.
- **Negative** — the token's location follows the user's default vault. Changing the default vault leaves the token in the old one, where reads still find it but `Set-YnabToken` writes a second copy to the new default.
- **Negative** — on a machine where the job and interactive use run as the same user, they share one SecretStore, so whatever unattended access the job later needs also affects how the personal token is protected.
- **Neutral** — the resolver has a single implementation until OAuth lands.
- **Neutral** — tests mock the SecretManagement cmdlets, so real vault behavior is not exercised in CI.
