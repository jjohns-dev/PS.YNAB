# ADR 5: Session-Only Delta Cache

Amends: ADR-0004

## Status

Accepted — 2026-11-15

Amended by [ADR-0006](0006-never-cache-filtered-lists.md) — 2026-11-16. Two statements below are now inaccurate and are left in place:

- The Decision bullet reading "We will cache list results in module memory…". Filtered lists are not cached; ADR-0006 excludes `Get-YnabTransaction` because deltas do not report an item that stops matching a filter.
- The Consequences bullet saying repeated reads download only changes, "which matters most for `Get-YnabPlan` and long transaction lists". Only `Get-YnabPlan` caches transaction history now.

Everything else in this record still stands.

## Context

- YNAB supports delta requests: a response carries `server_knowledge`, and sending it back as `last_knowledge_of_server` returns only what changed. A delta request is still one request, so it shrinks responses but does not reduce use of the 200-requests-per-hour limit.
- The read functions download whole lists on every call, and `Get-YnabPlan` downloads a plan's entire history.
- A daily alerter starts a new process each run and sends a handful of requests; interactive sessions read the same lists repeatedly.
- ADR-0003 keeps the module out of secret storage: the caller decides where credentials live. YNAB data is financial data, and a disk cache would also need a location per operating system, protection against concurrent writers, and handling of response-format changes between versions.
- YNAB's list responses carry the list and `server_knowledge` but no plan ID. `-PlanId` defaults to `last-used`, which YNAB resolves to whichever plan the user last opened, and can change during a session.
- Per YNAB's OpenAPI spec, deleted items of every type are included only in delta responses. ADR-0004 planned a switch to include them with step 3. Merging deltas into a cache removes deleted items, so such a switch could only show deletions seen since the session's first call.
- The options weighed for keyword plans, and why each was rejected, are in the [delta-cache design](../specs/delta-cache/design.md#alternatives-considered).

## Decision

- We will cache list results in module memory for the PowerShell session only, and never write YNAB data to disk.
- We will keep each cached list current by sending one delta request per call and merging the changes, so every call reflects YNAB's current data; no call is answered from the cache without a request.
- We will cache only calls made with an explicit plan ID. Calls with `last-used` or `default` bypass the cache and say so in their verbose output.
- We will return copies of cached data, so callers cannot change the cache.
- We will clear the cache on `Connect-Ynab` and `Disconnect-Ynab`, and provide `Clear-YnabCache`.
- We will not add `-IncludeDeleted` in step 3. It can be added later without breaking callers, for example if callers are ever given their own server knowledge to keep.

## Consequences

- **Positive** — repeated reads in a session download only changes, which matters most for `Get-YnabPlan` and long transaction lists.
- **Positive** — no YNAB data is written to disk by the module, so there is no data at rest, file location or concurrency to manage.
- **Positive** — cached results are never stale and never mix plans.
- **Negative** — with the default `-PlanId` of `last-used`, nothing is cached; users must set a plan ID default to benefit.
- **Negative** — a cached `Get-YnabPlan` holds a plan's whole history in memory for the session, and every cached call pays to copy its entry.
- **Negative** — caching saves no requests against the rate limit, and a daily alerter, starting fresh each run, gains nothing from it.
- **Negative** — the merge relies on YNAB marking removed items `deleted` in delta responses; an item removed without the flag would remain in the cache until it is cleared.
- **Neutral** — persisting server knowledge across runs remains possible later through the caller, in the spirit of ADR-0003, without changing this decision.
