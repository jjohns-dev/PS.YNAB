# OAuth: requirements

Step 4 of the plan in [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1); tracked in [#26](https://github.com/jjohns-dev/PS.YNAB/issues/26). Constrained by [ADR-0003](../../adr/0003-session-token-auth-and-default-plan.md) (session auth, no secret store, refreshed tokens handed back to the caller) and [ADR-0005](../../adr/0005-session-only-delta-cache.md) (cache cleared on connect and disconnect). The OAuth section of [docs/design.md](../../design.md#oauth-app-read-only-shipped) describes it as built.

## Problem / motivation

The only way to authenticate today is a personal access token, which has full read and write access and never expires. The spending alerter will run unattended, so it should hold a credential that can only read and that expires on its own. YNAB's OAuth authorization code grant with the `read-only` scope provides that: 2-hour access tokens, renewed with a refresh token. The module needs to obtain that authorization once, interactively, and then keep an unattended session working by refreshing it, without ever storing the tokens itself.

## Verified behavior this step builds on

From the spike on 2026-11-16 ([#26](https://github.com/jjohns-dev/PS.YNAB/issues/26#issuecomment-6930333899)) and YNAB's New OAuth Application form:

- An app accepts several redirect URIs, and the form recommends `urn:ietf:wg:oauth:2.0:oob` or `http://localhost[:port]` for local use. A registered `http://localhost:8765/callback` worked with PKCE and `state`.
- The `read-only` scope is enforced: a write returns `403 unauthorized_scope`.
- Access tokens last 7200 seconds.
- **Every refresh returns a new refresh token, and the previous refresh token is then rejected (`400 invalid_grant`).**
- **A refresh immediately revokes the previous access token (`401`).** Only the newest token pair is ever valid.
- Presenting an old refresh token does not revoke the newest one.

## User stories

- As a module user, I want to authorize the module once in my browser with read-only access, so that an unattended job never needs my full-access personal token.
- As the alerter's author, I want to start a session from a stored refresh token, so that a scheduled run needs no browser.
- As the alerter's author, I want each new refresh token handed to my code the moment it is issued, so that a crash later in the run cannot leave me holding a revoked token.
- As a module user, I want expired access tokens renewed automatically, so that a long session does not fail after two hours.
- As a module user, I want clear errors when authorization fails or the stored refresh token is no longer valid, so that I know to authorize again.

## Acceptance criteria

IDs are stable: new criteria are added at the end rather than renumbering.

### Authorizing in the browser

- **AC-1** WHEN the user authorizes interactively, THE SYSTEM SHALL open the browser to `https://app.ynab.com/oauth/authorize` with `response_type=code`, `scope=read-only`, a random `state`, and a PKCE `code_challenge` using `S256`.
- **AC-2** THE SYSTEM SHALL receive the authorization code on a listener bound only to the loopback redirect URI's host and port, and SHALL stop the listener when the code arrives, the wait times out, or an error occurs.
- **AC-3** WHEN no code arrives within the timeout, THE SYSTEM SHALL raise an error saying so, and SHALL NOT request a token.
- **AC-4** WHEN the returned `state` differs from the one sent, or the redirect carries an `error`, THE SYSTEM SHALL raise an error and SHALL NOT request a token.
- **AC-17** WHEN the listener cannot start, for example because the port is already in use, THE SYSTEM SHALL raise an error naming the redirect URI and suggesting `-RedirectUri` with another registered port, before opening the browser.
- **AC-5** THE SYSTEM SHALL exchange the code at `https://app.ynab.com/oauth/token` with the client ID, client secret, redirect URI, code and PKCE `code_verifier`.

### Resuming from a stored refresh token

- **AC-6** WHEN the user starts a session from a refresh token, THE SYSTEM SHALL redeem it immediately, so an invalid token fails at connect time rather than on the first read.

### The session

- **AC-7** A successful authorization or resume SHALL hold the access token, refresh token and access-token expiry in module memory only, replacing any existing session, personal token or OAuth, and SHALL clear the session cache (ADR-0005).
- **AC-8** THE SYSTEM SHALL accept the client secret, refresh token and any token only as `SecureString`, and SHALL NOT write a token, client secret, code or code verifier to any output stream, including in error records.
- **AC-9** `Disconnect-Ynab` SHALL clear an OAuth session as it clears a personal-token session.
- **AC-10** Every read function SHALL work unchanged with an OAuth session; no public read function gains a parameter.

### Refreshing

- **AC-11** WHEN a request is about to be sent and the access token expires within 60 seconds, THE SYSTEM SHALL refresh first.
- **AC-12** WHEN YNAB answers a request with `401` during an OAuth session, THE SYSTEM SHALL refresh once and resend the request once.
- **AC-13** EVERY time a refresh succeeds, during a resume, before a request, or after a `401`, THE SYSTEM SHALL hand the new refresh token to the caller (see open question 1) before it sends any further request.
- **AC-14** WHEN a refresh fails, THE SYSTEM SHALL end the OAuth session and raise an error that says the stored refresh token is no longer valid and that the user must authorize again.

### Module

- **AC-15** New and changed functions SHALL have comment-based help and tests that never reach the network or open a browser. CI SHALL pass with the `min-tests` floor re-derived per AGENTS.md.
- **AC-16** `docs/design.md` SHALL move the verified OAuth facts above from "unverified" into its facts table, and describe the OAuth flow as built.

## Out of scope

- Storing tokens or client credentials anywhere: the caller's job (ADR-0003).
- Coordinating several processes that share one authorization. Because a refresh revokes the other process's tokens, the documentation states that each process needs its own authorization.
- The implicit grant (no refresh token), any scope other than `read-only` (none exists), and revoking authorizations through the API.
- The alerter itself and where it runs (step 6, [#16](https://github.com/jjohns-dev/PS.YNAB/issues/16)).

## Resolved questions

- **How new refresh tokens reach the caller (AC-13):** a scriptblock passed when connecting, for example `-OnTokenRefresh { param ($Token) Set-Secret -Name YnabRefreshToken -Secret $Token.RefreshToken }`, called synchronously after every refresh with the new refresh token (`SecureString`) and the access-token expiry. If it throws, the session keeps working in memory and the error surfaces, so the caller knows its stored token is stale. Rejected: a getter the caller reads after each command (a run that refreshes and then fails never reaches it), and a PowerShell event (more moving parts for the same result).
- **Out-of-band code entry:** supported, as a switch alongside the localhost listener, because the alerter's host is undecided and may have no local browser.
- **One command:** OAuth adds parameter sets to `Connect-Ynab` (client credentials to authorize; client credentials plus a refresh token to resume), as ADR-0003 decided, instead of the separate `Connect-YnabOAuth` that `docs/design.md` planned. One command starts every kind of session, and `Disconnect-Ynab` already ends any kind.
- **`Update-YnabOAuthToken` is dropped:** automatic refresh (AC-11, AC-12) and resume (AC-6) cover it; it can be added later without breaking anyone.
- **Defaults:** `-RedirectUri` defaults to `http://localhost:8765/callback`, the value the spike verified, and is overridable; the browser wait is 5 minutes. Port 8765 has no special meaning: it came from a third-party YNAB tool seen in research, is above 1024 (no administrator rights needed) and below the operating systems' ephemeral port ranges, and avoids common development ports. Whether other software commonly uses it was not checked, so a port already in use must produce a clear error.

## Open questions

None.
