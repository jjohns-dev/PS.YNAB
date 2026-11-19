# PS.YNAB design

The standing design of the module: what it wraps, the rules every function follows, and the auth model. Each fact here has one authoritative home; this page states it once or links to where it lives.

| Topic | Authoritative source |
|---|---|
| Why a decision was made | [`docs/adr/`](adr/) |
| How one step was built (requirements, design, tasks) | [`docs/specs/`](specs/) |
| Which functions ship | `FunctionsToExport` in [`PS.YNAB.psd1`](../PS.YNAB.psd1) |
| How a shipped function behaves | Its comment-based help (`Get-Help <name> -Full`) |
| How users connect and supply the token | [README: Connecting](../README.md#connecting) |
| Build, CI and contributor conventions | [AGENTS.md](../AGENTS.md), [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Plan, progress and open questions | Tracking issue [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1) |

## Purpose

`PS.YNAB` wraps the [YNAB API](https://api.ynab.com), base URI `https://api.ynab.com/v1`. Its first consumer is a daily spending-anomaly alerter that is planned to run unattended with a read-only OAuth credential; interactive use, including writes, uses a personal access token. Why this is its own module rather than an existing one: [ADR-0001](adr/0001-dedicated-module-on-the-shared-harness.md).

## Design rules

Every function follows these.

1. **One HTTP caller, two fixed hosts.** The private `Invoke-YnabRequest` is the only function that calls `Invoke-RestMethod`. It sends only to the API base URI and to YNAB's OAuth token endpoint `https://app.ynab.com/oauth/token`, and neither is configurable. It owns bearer authentication, YNAB error unwrapping, query strings, bounded 429 retries and OAuth token refresh ([foundation spec](specs/foundation/design.md), [ADR-0007](adr/0007-oauth-sessions-with-rotating-refresh-tokens.md)).
2. **Plans, not budgets.** Paths use `/plans/{plan_id}`; names use `Plan` and `-PlanId` ([ADR-0002](adr/0002-follow-the-plans-naming.md)).
3. **Output keeps YNAB's shape.** YNAB's property names and casing; amounts converted from milliunits (1000 = 1.00) to `System.Decimal` at any depth, so callers never see raw milliunits; `*_currency` dropped and `*_formatted` kept; deleted items dropped; `plan_id` added to plan objects for pipeline binding ([ADR-0004](adr/0004-output-objects-keep-ynab-shape.md)). Amounts going *to* YNAB go through `ConvertTo-Milliunit`, which takes the value untyped and converts it by type: a double or single is rounded to 15 or 7 significant digits, a string is parsed with the invariant culture. That gives the same result before and after .NET 11 (PowerShell 7.7), whose correctly rounded double-to-decimal conversion would otherwise turn `12.34` into `12.339999999999999857891452848` ([#18](https://github.com/jjohns-dev/PS.YNAB/issues/18)). A parameter that accepts an amount is therefore never typed `[System.Decimal]`, since binding converts before the function can.
4. **Default plan.** Every `-PlanId` defaults to `last-used`, is validated as a UUID, `last-used` or `default`, and is overridden per session with `$PSDefaultParameterValues['*-Ynab*:PlanId']`. Module functions pass `-PlanId` explicitly to each other, because profile defaults do not reach internal calls ([ADR-0003](adr/0003-session-token-auth-and-default-plan.md)).
5. **Session auth, no secret store.** Tokens and the OAuth client secret are accepted only as `SecureString` through `Connect-Ynab`, held for the session, sent only to the two fixed hosts of rule 1, and never written to any output stream; new OAuth refresh tokens are handed to the caller's `-OnTokenRefresh` scriptblock. The module depends on no secret store and never registers, configures or unlocks a vault; the caller decides where secrets live ([ADR-0003](adr/0003-session-token-auth-and-default-plan.md)).
6. **Respect the rate limit; cache with delta requests.** Each read sends one request. List reads made with a plan ID are cached for the session, in memory only, and kept current with delta requests (`server_knowledge` sent back as `last_knowledge_of_server`), so later calls download only changes; `last-used` and `default` are not cached. Delta requests shrink responses but do not save requests ([ADR-0005](adr/0005-session-only-delta-cache.md)). A list YNAB filters, which includes every transaction list, is never cached, because deltas do not report an item that stops matching the filter ([ADR-0006](adr/0006-never-cache-filtered-lists.md)).
7. **Writes are guarded.** Every write function uses `[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]` and honors `-WhatIf` / `-Confirm`.
8. **One module.** Read and write functions ship together; a read-only job is protected by its read-only OAuth credential, not by which functions it loads.
9. **Naming.** Exported functions are `Verb-Ynab<Noun>` with approved verbs ([ADR-0001](adr/0001-dedicated-module-on-the-shared-harness.md)).

## YNAB API facts

Checked against the [API docs](https://api.ynab.com) and the [OpenAPI spec](https://api.ynab.com/papi/open_api_spec.yaml) (v1.90.0); the date is when each was last checked.

| Fact | Checked |
|---|---|
| The rate limit is 200 requests per hour per access token, on a rolling window. A 429 says only to wait and retry: no `Retry-After` header is documented, and the `X-Rate-Limit` header was removed in v1.73.0. | 2026-11-10 |
| `read-only` is the only documented OAuth scope; a write with a read-only token returns 403 `unauthorized_scope`, observed in the [#26 spike](https://github.com/jjohns-dev/PS.YNAB/issues/26#issuecomment-6930333899). | 2026-11-16 |
| OAuth access tokens expire 2 hours after they are granted, and the token response carries `expires_in` (7200 in the spike). The authorization code grant supports refresh tokens; the implicit grant does not. | 2026-11-16 |
| An OAuth app accepts several redirect URIs, one per line; the registration form recommends `urn:ietf:wg:oauth:2.0:oob` or `http://localhost[:port]` for local use. A localhost redirect with PKCE and `state` worked in the spike. | 2026-11-16 |
| Every refresh returns a new refresh token; the previous refresh token is then rejected with 400 `invalid_grant`, and reusing it does not revoke the newest one. | 2026-11-16 |
| A refresh revokes the previous access token at once (401), not at its expiry, so only the newest token pair is ever valid. | 2026-11-16 |
| Restricted mode limits an OAuth app to 25 access tokens for users other than the app's owner. | 2026-11-10 |
| Errors return `{ "error": { "id", "name", "detail" } }`. | 2026-11-10 |
| `plan_id` accepts `last-used`, and `default` when default plan selection is enabled. | 2026-11-10 |
| `/plans/{plan_id}` is the primary path. `/budgets/{budget_id}` still works and returns the original response key names. | 2026-11-10 |
| Deleted items of every type "will only be included in delta requests". | 2026-11-11 |
| Category amounts from the categories endpoints are for the current plan month in UTC. | 2026-11-11 |
| The unit of an account's `debt_interest_rates` map is not documented. | 2026-11-11 |

Still unverified: how YNAB displays the code for the out-of-band redirect.

Other references: [Developer Settings](https://app.ynab.com/settings/developer) (tokens and OAuth apps); OAuth endpoints `https://app.ynab.com/oauth/authorize` and `https://app.ynab.com/oauth/token`; the [2026-04-29 API update](https://www.ynab.com/whats-new/ynabs-api-gets-even-better). Prior art: the only PowerShell Gallery module is `Posh-YNAB` 0.2.4, last published 2019-01-02 (rechecked 2026-11-10), which predates the plans rename and the 2026 write endpoints.

## Authentication

### Personal access token (shipped)

Full read/write access, no scopes, no expiry; for interactive use, including writes. Created under Developer Settings and shown once. How to connect and supply it safely: [README: Connecting](../README.md#connecting). To rotate, create a new token, update your store, run `Connect-Ynab`, verify, then revoke the old token. Use one token per use case.

### OAuth app, read-only (shipped)

For unattended jobs. Why it works this way: [ADR-0007](adr/0007-oauth-sessions-with-rotating-refresh-tokens.md); how it was built: the [OAuth spec](specs/oauth/design.md); parameters and examples: `Get-Help Connect-Ynab -Full`.

- **Register** under Developer Settings → New Application with the redirect URIs `http://localhost:8765/callback` (the `-RedirectUri` default) and, for hosts without a reachable browser, `urn:ietf:wg:oauth:2.0:oob`. The client ID and secret live wherever the job's host keeps credentials.
- **Authorize once** with `Connect-Ynab -ClientId -ClientSecret`: the browser opens YNAB's authorize page with the `read-only` scope, `state` and a PKCE `S256` challenge; the code arrives on a loopback `HttpListener` (or is typed, with `-OutOfBand`) and is exchanged at the token endpoint.
- **Resume** in a later process with `-RefreshToken`; it is redeemed at once.
- **Refresh automatically** in `Invoke-YnabRequest`: before a request when the access token expires within 60 seconds, and once after a 401. Because each refresh revokes the previous tokens, every new refresh token is handed to the caller's `-OnTokenRefresh` scriptblock before any further request. The module stores nothing (rule 5).
- **One authorization per process.** A refresh in one process revokes the tokens of every other process using the same authorization.
- **Revoke** by removing the app under Authorized Applications in Developer Settings.
- The implicit grant is not used, because it has no refresh token.

Both kinds of session live in the same place: the access token is the session token every read function already uses, so OAuth changed `Connect-Ynab`, `Disconnect-Ynab` and `Invoke-YnabRequest` and no read function.

## Planned functions

Shipped functions are listed in the manifest and documented in their help (see the table at the top). These are planned and not yet built:

| Function | Purpose | Step |
|---|---|---|
| `New-YnabTransaction` | `POST /plans/{plan_id}/transactions` | 5 |
| `Update-YnabTransaction` | `PUT`/`PATCH /plans/{plan_id}/transactions` (approve, recategorize) | 5 |
| `Set-YnabCategoryBudget` | `PATCH /plans/{plan_id}/months/{month}/categories/{category_id}` | 5 |

## Security

- Never commit tokens, client secrets or refresh tokens, including in test fixtures; tests use made-up sentinel tokens.
- Scheduled jobs use the read-only OAuth credential. The personal token stays on the interactive machine.
- Rotate the personal token about every 90 days.
