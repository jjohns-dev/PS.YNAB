# ADR 7: OAuth Sessions with Rotating Refresh Tokens

## Status

Accepted — 2026-11-18

## Context

- ADR-0003 starts sessions with `Connect-Ynab`, keeps them in module memory only, depends on no secret store, and says that at the OAuth step "refreshed tokens will be handed back to the caller to persist". It does not say when or how.
- A spike on 2026-11-16 against the maintainer's plan ([#26](https://github.com/jjohns-dev/PS.YNAB/issues/26#issuecomment-6930333899)) found that every refresh returns a new refresh token and the previous refresh token is then rejected (`400 invalid_grant`); that a refresh revokes the previous access token immediately (`401`), not at its 2-hour expiry; and that presenting an old refresh token does not revoke the newest one.
- Because of that rotation, a caller that refreshes and then fails before saving the new refresh token holds a revoked token, and must authorize again in a browser. Only the newest token pair is valid at any moment, so two processes using one authorization revoke each other's tokens.
- The alerter will run unattended, starting each run from a stored refresh token.
- Design rule 1 makes `Invoke-YnabRequest` the only caller of `Invoke-RestMethod`, sending only to the fixed base URI `https://api.ynab.com/v1`. YNAB's token endpoint is on another host, `https://app.ynab.com/oauth/token`, with a form body and a different error shape.

## Decision

- We will hand every new refresh token to the caller through a scriptblock passed to `Connect-Ynab` as `-OnTokenRefresh`, called synchronously after the initial code exchange and after every refresh, **before any further request is sent**, with a separate `SecureString` copy of the refresh token and the access token's expiry.
- We will keep the session working if that scriptblock throws, and write a non-terminating error, so the caller can make it fatal with `$ErrorActionPreference`.
- We will refresh an OAuth session before a request whose access token expires within 60 seconds, and once after a `401`; a failed refresh ends the session with an error saying to authorize again.
- We will treat one authorization as belonging to one process, and document that rather than coordinate between processes.
- We will add YNAB's token endpoint to `Invoke-YnabRequest` as a second fixed host, used only for token requests, so it remains the only HTTP caller and neither host is configurable.

## Consequences

- **Positive** — a caller that saves the token in `-OnTokenRefresh` never holds a revoked token after a refresh, whatever fails later in the run.
- **Positive** — read functions and the cache work unchanged with OAuth sessions, and personal-token sessions are unaffected.
- **Negative** — the caller's scriptblock runs in the middle of an unrelated read; a slow or failing save delays or reports an error on that read.
- **Negative** — by default a failing save is only a non-terminating error; an unattended caller that does not set `$ErrorActionPreference = 'Stop'` can continue with a stale stored token and fail on its next run.
- **Negative** — every process that needs OAuth access, such as the alerter and an interactive session, needs its own browser authorization.
- **Neutral** — if YNAB stops rotating refresh tokens, the same contract still works; the scriptblock would just receive an unchanged token.
