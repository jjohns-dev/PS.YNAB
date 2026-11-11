# Foundation: requirements

Step 1 of the plan in [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1); tracked in [#4](https://github.com/jjohns-dev/PS.YNAB/issues/4). Constrained by [ADR-0002](../../adr/0002-follow-the-plans-naming.md) and [ADR-0003](../../adr/0003-session-token-auth-and-default-plan.md).

## Problem / motivation

Every planned `PS.YNAB` function needs to authenticate to the YNAB API, send a request, interpret YNAB's error responses, survive the 200-requests-per-hour rate limit, and convert milliunit amounts. Without one shared layer, each function would reimplement these and drift. The module has no functions yet, so nothing else can be built or tested until this layer exists.

## User stories

- As a module user, I want to start a session once with my personal token, so that later commands authenticate without me passing the token each time.
- As a module user, I want to end the session, so that the token is no longer held in memory.
- As a module user, I want YNAB errors reported with YNAB's own error ID and explanation, so that I can tell a bad token from a wrong plan ID from a rate limit.
- As a module user, I want a brief rate-limit hit to be retried for me, so that a transient 429 does not fail my command.
- As a module author, I want one private function that performs every HTTP request, so that auth, errors and retries are implemented and tested once.
- As a module author, I want amount conversion helpers, so that no function exposes raw milliunits.

## Acceptance criteria

### `Connect-Ynab`

- **AC-1** WHEN called with `-Token <securestring>`, THE SYSTEM SHALL validate the token with one `GET /user` request and, on success, hold the token in module session state for later requests and write nothing to the success stream.
- **AC-2** WHEN validation fails, THE SYSTEM SHALL throw the request's terminating error and leave any existing session unchanged.
- **AC-3** WHEN `-Token` is given a plain string, THE SYSTEM SHALL refuse it at parameter binding.
- **AC-4** WHEN called while a session already exists and validation succeeds, THE SYSTEM SHALL replace the existing session.
- **AC-5** THE SYSTEM SHALL NOT write the token, or any object containing it, to any output stream.

### `Disconnect-Ynab`

- **AC-6** WHEN called, THE SYSTEM SHALL clear and dispose the session token.
- **AC-7** WHEN called with no session, THE SYSTEM SHALL complete without error.

### `Invoke-YnabRequest` (private)

- **AC-8** THE SYSTEM SHALL send every request to the base URI `https://api.ynab.com/v1`, with no parameter or setting to change it.
- **AC-9** THE SYSTEM SHALL authenticate using `Invoke-RestMethod -Authentication Bearer -Token`, never a header string it builds.
- **AC-10** WHEN no session exists, THE SYSTEM SHALL throw a terminating error that names `Connect-Ynab` and makes no HTTP call.
- **AC-11** WHEN the response is successful, THE SYSTEM SHALL return the response's `data` object.
- **AC-12** WHEN a request body is supplied, THE SYSTEM SHALL send it as JSON with content type `application/json`.
- **AC-13** WHEN YNAB returns an error response, THE SYSTEM SHALL throw a terminating error whose message includes the HTTP status code and YNAB's `error.id`, `error.name` and `error.detail`.
- **AC-14** WHEN YNAB returns 401, THE SYSTEM SHALL say in the error message that the token may be invalid or revoked and that `Connect-Ynab` must be run again.
- **AC-15** WHEN YNAB returns 429, THE SYSTEM SHALL retry up to 3 times, waiting 15, 30 and 60 seconds before the first, second and third retry, then throw the 429 error as in AC-13. The retry count and delays are fixed, not configurable.
- **AC-16** WHEN an error response body is not YNAB's error shape, THE SYSTEM SHALL still throw a terminating error that includes the HTTP status code.
- **AC-17** THE SYSTEM SHALL NOT include the token in any error record, verbose message or debug message.
- **AC-18** THE SYSTEM SHALL remain the only function in the module that calls `Invoke-RestMethod`.

### `ConvertFrom-Milliunit` / `ConvertTo-Milliunit` (private)

- **AC-19** WHEN given a milliunit integer, `ConvertFrom-Milliunit` SHALL return the amount as a `[decimal]` equal to the input divided by 1000 (for example, `-12340` → `-12.34`).
- **AC-20** WHEN given a `[decimal]` amount with at most three decimal places, `ConvertTo-Milliunit` SHALL return a `[long]` equal to the amount times 1000 (for example, `12.34` → `12340`).
- **AC-21** WHEN given an amount with more than three decimal places, `ConvertTo-Milliunit` SHALL throw a terminating error rather than round.
- **AC-22** Both functions SHALL accept pipeline input.
- **AC-23** Round-tripping any value with at most three decimal places SHALL return the original value exactly.
- **AC-27** WHEN given a value that is not a whole number of milliunits, `ConvertFrom-Milliunit` SHALL throw a terminating error rather than round. (Added during PR review; numbered last so existing IDs stay stable.)

### Module

- **AC-24** `Connect-Ynab` and `Disconnect-Ynab` SHALL be exported and listed in `FunctionsToExport`; the private functions SHALL NOT be exported.
- **AC-25** Every new function SHALL have comment-based help with a `.NOTES` `Status:` line and a `Tests/Unit/<Verb-Noun>.tests.ps1` that never reaches the network.
- **AC-26** CI (`validate (ubuntu-latest)` and PSScriptAnalyzer) SHALL pass.

## Out of scope

- OAuth (`Connect-YnabOAuth`, `Update-YnabOAuthToken`, refresh): step 4.
- Delta requests and lookup caching: step 3.
- Any public read or write function beyond `Connect-Ynab` / `Disconnect-Ynab`: steps 2 and 5.
- Retrying errors other than 429, such as 5xx or network failures.
- Tracking or reporting the remaining rate-limit budget.

## Resolved questions

1. **Validate the token on connect?** Yes, with one `GET /user` request; nothing is output on success (AC-1, AC-2).
2. **429 retry bounds.** No `Retry-After` header is documented and the window is a rolling hour, so retries are short and fixed: 3 retries at 15, 30 and 60 seconds (AC-15).
3. **More than three decimal places in `ConvertTo-Milliunit`.** Throw rather than round silently (AC-21).
