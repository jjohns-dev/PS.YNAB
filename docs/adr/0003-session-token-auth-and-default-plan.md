# ADR 3: Session Token Auth and the Default Plan

## Status

Proposed — 2026-11-10

## Context

- YNAB offers two auth schemes: a personal access token (full read/write, no scopes, no expiry) and an OAuth authorization code grant (`read-only` scope, access tokens that expire 2 hours after they are granted, refresh tokens).
- Interactive use needs only the personal token. Where the unattended alerter will run, and so where its credentials will live, is undecided.
- Two OAuth details are unverified: which redirect URIs an OAuth app accepts, and whether every refresh issues a new refresh token.
- An OAuth session changes during use: each refresh replaces the access token, so whatever holds the session must carry state from one call to the next.
- The repo's cross-cutting rules make `Invoke-YnabRequest` the only HTTP caller and the owner of the auth header and OAuth refresh.
- Users keep secrets in different places: SecretManagement vaults, environment variables, CI secrets, cloud secret managers. The maintainer uses SecretManagement but wants the token passed in, as AWS.Tools and CrowdStrike's PSFalcon do, rather than read from a store the module chooses.
- PowerShell has no security boundary inside a session: code outside a module can read the module's script-scope variables (observed).
- `SecureString` does not encrypt its contents on non-Windows platforms, and Microsoft recommends against it for new .NET development. It still keeps a value out of console output and formatting.
- A `[securestring]` parameter refuses a plain string at binding time (observed).
- `Invoke-RestMethod -Authentication Bearer -Token <securestring>` sends the token without the caller building a header string, and refuses an `http://` URI unless `-AllowUnencryptedAuthentication` is given (observed).
- PSReadLine 2.4.5's default history handler keeps lines containing `-AsPlainText` out of the history file, but saves `$t = '<token>'` to it (observed).
- `$PSDefaultParameterValues` entries bind on calls made from the session but not on calls one module function makes to another; a scriptblock value runs on each call; and a wildcard key such as `'*-Ynab*:Token'` binds to a matching command from any module (all observed).
- Most endpoints take a `plan_id`; the API accepts `last-used` without the caller knowing an ID. The docs do not define what "used" means.
- The maintainer already sets per-session defaults for other modules with `$PSDefaultParameterValues` in a pwsh profile.

## Decision

- We will support personal-token auth only until the OAuth step in the plan.
- We will add `Connect-Ynab -Token <securestring>`, which holds the token in module session state, and `Disconnect-Ynab`, which clears and disposes it.
- We will have `Invoke-YnabRequest` get the token from one private resolver, which fails with an error naming `Connect-Ynab` when no session exists. OAuth will be added by extending `Connect-Ynab` and the resolver.
- We will not depend on SecretManagement or any other secret store. The caller decides where the token lives and passes it in. At the OAuth step, refreshed tokens will be handed back to the caller to persist.
- We will accept the token only as `[securestring]`, and send it only through `Invoke-RestMethod -Authentication Bearer -Token`, never as a header string the module builds.
- We will hardcode the base URI `https://api.ynab.com/v1` with no override, so the token is sent to no other host.
- We will never emit the token in output, verbose, debug or error records, and no exported command will return the session. Tests will check error records for the token.
- We will not add a `-Token` parameter to every public function with a `$PSDefaultParameterValues` default (the evaluated alternative). It reads the vault lazily on each call, but it cannot carry a refreshed OAuth session between calls, every public function and internal call would have to pass the token, and a wildcard default hands the token to matching commands in other modules.
- We will default every `-PlanId` parameter to `'last-used'`, keep no module-level default-plan state, and document `$PSDefaultParameterValues['*-Ynab*:PlanId']` as the per-session override.
- We will have module functions pass `-PlanId` explicitly to any module function they call.
- We will defer OAuth and the scheduled job's host and credential source to their steps in the plan.

## Consequences

- **Positive** — the module has no runtime dependency, and the token can come from any source: a vault, an environment variable, a CI secret or a prompt.
- **Positive** — OAuth fits the same shape later, which lets unattended jobs use a read-only token with 2-hour access tokens instead of the full-access personal token.
- **Positive** — the module sends the token only to `api.ynab.com` over HTTPS and never holds it as a plain header string.
- **Positive** — the default plan needs no module code, and a user with one plan needs no setup at all.
- **Negative** — every session must run `Connect-Ynab` before any other command. Connecting from a profile reads the secret store at shell start, which prompts for a locked vault, unless it is wrapped in a function called on demand.
- **Negative** — the token stays in process memory for the whole session, unencrypted on macOS and Linux and readable by any code in the session, until `Disconnect-Ynab` or the shell exits.
- **Negative** — the module cannot persist refreshed OAuth tokens, so every OAuth caller must store them back itself.
- **Negative** — there is no per-call token, so working with two YNAB accounts in one session means reconnecting between them.
- **Negative** — a misspelled `$PSDefaultParameterValues` key or parameter name is ignored silently, so calls fall back to `last-used`, which may be a different plan.
- **Negative** — because `last-used` is undefined in the docs, unattended consumers such as the alerter must pass an explicit `-PlanId` rather than rely on the default.
- **Neutral** — users must be told how to supply the token safely (from a vault or `Read-Host -AsSecureString`, never assigned as a plain string), because the module cannot enforce it.
- **Neutral** — the resolver has a single implementation until OAuth lands.
