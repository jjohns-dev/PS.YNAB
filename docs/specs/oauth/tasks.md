# OAuth: tasks

Implements [design.md](design.md). Two PRs, in order; each leaves the module importable with all tests passing. Check a box only after its verification has run and passed, in the same PR that completes the task. Both PRs reference [#26](https://github.com/jjohns-dev/PS.YNAB/issues/26); PR 2's description uses `closes #26`.

## Standard checks before each PR

S1 to S5 as in the [core-reads tasks](../core-reads/tasks.md#standard-checks-before-each-pr), plus S6 from the [delta-cache tasks](../delta-cache/tasks.md#standard-checks-before-each-pr) (re-derive `min-tests`). Also:

- **S7** No secret reaches an output stream: each new test file that handles tokens asserts a sentinel token, secret and code appear in no error record, verbose, debug, warning or information output. Verify: those tests pass, and fail against a scratch copy that writes the sentinel to verbose.

## PR 1: refresh machinery

- [x] **1.1** Write `docs/adr/0007-oauth-sessions-with-rotating-refresh-tokens.md` with status `Proposed`, covering the design's ADR check.
  - Verify: five sections, at least one negative consequence, and Context citing #26's results.
- [x] **1.2** Initialize `$script:YnabOAuth = $null` in `PS.YNAB.psm1`.
  - Verify: the module imports and `InModuleScope PS.YNAB { $null -eq $script:YnabOAuth }` is `True`.
- [x] **1.3** Add the `_grant` parameter set to `Invoke-YnabRequest`, with tests: form POST to `https://app.ynab.com/oauth/token` with no bearer token and debug off; OAuth error bodies (`{ "error": "invalid_grant" }`) become `YnabOAuth.invalid_grant`; no form value in any stream (AC-5, AC-8).
  - Verify: `Invoke-Pester` on `Invoke-YnabRequest.tests.ps1` passes; existing tests unchanged.
- [x] **1.4** Add `Private/Update-YnabSessionToken.ps1` and its tests: rotation of both tokens and `ExpiresAt`; the scriptblock called once, with a separate copy, before returning; a throwing scriptblock leaves the session working and writes the non-terminating `YnabOAuthTokenRefreshCallbackFailed`; a failed refresh clears both session variables and raises `YnabOAuthRefreshFailed` (AC-13, AC-14).
  - Verify: `Invoke-Pester` on `Update-YnabSessionToken.tests.ps1` passes.
- [x] **1.5** Make API requests in an OAuth session refresh before sending when `ExpiresAt` is within 60 seconds, and refresh then resend once on `401`, with tests: no refresh for a personal-token session or an explicit `-Token`; no second retry; the refreshed token is the one resent (AC-11, AC-12).
  - Verify: `Invoke-Pester` on `Invoke-YnabRequest.tests.ps1` passes.
- [x] **1.6** Clear and dispose the OAuth record in `Disconnect-Ynab`, and in `Connect-Ynab -Token`, with tests (AC-7, AC-9).
  - Verify: `Invoke-Pester` on `Disconnect-Ynab.tests.ps1` and `Connect-Ynab.tests.ps1` passes.
- [x] **1.7** Standard checks S1 to S7. Before merge, push a final commit setting ADR-0007 to `Accepted`.
  - Verify: as listed; ADR-0007 shows `Accepted` on `main` after merge.

## PR 2: connecting

- [x] **2.1** Add `Private/New-YnabOAuthRequest.ps1` and tests: 43-character verifier, `S256` challenge matching it, random `state`, and an authorize URL with `response_type=code`, `scope=read-only`, the escaped redirect URI, `state`, `code_challenge` and `code_challenge_method=S256` (AC-1).
  - Verify: `Invoke-Pester` on `New-YnabOAuthRequest.tests.ps1` passes; the challenge is checked against an independent SHA-256 of the verifier.
- [x] **2.2** Add `Private/Receive-YnabAuthorizationCode.ps1` and tests, using a real listener on a port chosen at run time and a thread job as the browser, with `Start-Process` always mocked: code received; wrong path ignored; `error` and `state` mismatch rejected; timeout raises `YnabOAuthTimeout`; a port in use raises `YnabOAuthListenerFailed` before `Start-Process` is called; a non-loopback host is rejected; the listener is stopped on every path (AC-2, AC-3, AC-4, AC-17).
  - Verify: `Invoke-Pester` on `Receive-YnabAuthorizationCode.tests.ps1` passes locally and in CI (Linux).
- [x] **2.3** Add the `_authorize` and `_resume` sets to `Connect-Ynab`, with tests: binding for each set; authorize exchanges the code with the verifier; out-of-band uses the `oob` redirect and a mocked `Read-Host`; resume redeems at once; the scriptblock receives the first refresh token; without a scriptblock, a warning; the previous session and the cache are cleared (AC-1 to AC-7, AC-13).
  - Verify: `Invoke-Pester` on `Connect-Ynab.tests.ps1` passes.
- [x] **2.4** Update `docs/design.md`: rule 1 (two fixed hosts), the facts table (from #26), the OAuth section as built, and the planned-functions table; add an OAuth example to the README's Connecting section that links to the design rather than restating it (AC-16).
  - Verify: no remaining "unverified" note covered by #26, `Connect-YnabOAuth` and `Update-YnabOAuthToken` no longer listed, links resolve.
- [x] **2.5** **You recreate the OAuth app** with redirect URIs `http://localhost:8765/callback` and `urn:ietf:wg:oauth:2.0:oob`, store the client ID and secret, and **run the live check snippet** (provided in the PR).
  - Verify: every line it prints is `True` (or the expected status); results recorded here, including how YNAB shows the out-of-band code.
  - Result (2026-11-18, maintainer's plan, [#29](https://github.com/jjohns-dev/PS.YNAB/pull/29)): all six lines as expected. Loopback authorization read `True` with 1 token saved; a forced expiry refreshed before the request (`True`, 2); a rejected access token refreshed after the `401` and resent (`True`, 3); a resume read `True` (4); resuming from an already used refresh token raised `YnabOAuthRefreshFailed` and left no session (`YnabNotConnected`); out-of-band authorization read `True` (5).
  - Out-of-band display: YNAB opens a page titled "OAuth Authorization Code" showing the code, with the warning "This code will never be visible again so you should copy it now!" and a Back button.
- [x] **2.6** Standard checks S1 to S7, with the PR description using `closes #26`.

## After the last merge

- [x] **3.1** Tick step 4 in issue #1 with links to #26 and both PRs, and tick this task in the next PR that touches the repo.
  - Verify: issue #1 shows step 4 checked.
