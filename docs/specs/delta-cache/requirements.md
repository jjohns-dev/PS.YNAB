# Delta cache: requirements

Step 3 of the plan in [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1); tracked in [#21](https://github.com/jjohns-dev/PS.YNAB/issues/21). Follows the [design rules](../../design.md#design-rules), especially rule 6 (rate limit) and rule 3 (output shape, [ADR-0004](../../adr/0004-output-objects-keep-ynab-shape.md)).

## Problem / motivation

Every list read downloads the whole list again, and `Get-YnabPlan` downloads a plan's entire history. YNAB supports delta requests: a response carries `server_knowledge`, and sending it back as `last_knowledge_of_server` returns only what changed since. Using them keeps responses small for interactive sessions that read the same data repeatedly, while each call still reflects the current state.

**Decided before this spec** ([#21](https://github.com/jjohns-dev/PS.YNAB/issues/21)): the cache lives only in the PowerShell session's memory. Nothing is written to disk. Persisting across runs, if ever needed, would be caller-held (functions take and return server knowledge), in the spirit of [ADR-0003](../../adr/0003-session-token-auth-and-default-plan.md).

A delta request is still one request, so delta caching shrinks responses but does not reduce request count against the 200-per-hour limit.

## User stories

- As an interactive user, I want repeated reads in a session to download only what changed, so that large plans and transaction lists stay fast.
- As a module user, I want every read to reflect YNAB's current data, so that caching never shows me stale results.
- As a module user, I want to clear the cache, so that I can force a full download when I suspect a problem.
- As a module user, I want cached data gone when I disconnect or switch tokens, so that one session's data never leaks into another's.

## Acceptance criteria

IDs are stable: new criteria are added at the end rather than renumbering.

### Which calls are cached

- **AC-1** THE SYSTEM SHALL cache the results of these calls, whose endpoints accept `last_knowledge_of_server` per YNAB's OpenAPI spec: `Get-YnabPlan`; `Get-YnabAccount`, `Get-YnabCategory`, `Get-YnabPayee` and `Get-YnabMonth` without an ID or month; and `Get-YnabTransaction` without `-TransactionId`.
  - **Changed during PR 2 (2026-11-16):** `Get-YnabTransaction` is not cached after all. The live check showed a delta does not report a transaction that stops matching a filter, so the merged list kept it; see [ADR-0006](../../adr/0006-never-cache-filtered-lists.md).
- **AC-2** Calls for a single item (`-AccountId`, `-CategoryId`, `-PayeeId`, `-Month`, `-TransactionId`) and `Get-YnabPlanList` SHALL behave as before, with no cache.

### Cache behavior

- **AC-3** WHEN a cached call is made with no cache entry for the same plan, endpoint and query, THE SYSTEM SHALL send a full request and store the result with the response's `server_knowledge`.
- **AC-4** WHEN a cached call is made with a cache entry for the same plan, endpoint and query, THE SYSTEM SHALL send one request with `last_knowledge_of_server` set to the stored value, merge the changes into the entry, and store the new `server_knowledge`.
- **AC-5** Merging SHALL replace changed items, add new items, and remove items the response marks `deleted`, at every level that YNAB returns, such as transactions and their subtransactions.
- **AC-6** The items a cached call returns SHALL be the same items a full request would return at that moment, with the same values.
- **AC-7** Every cached call SHALL still send exactly one request. No call is answered from the cache without asking YNAB for changes (see open question 1).
- **AC-8** Entries SHALL be kept apart by plan, endpoint and query, so different plans, filters or accounts never share or mix results. A plan given as `last-used` or `default` SHALL NOT share an entry with the same plan given by its ID (see the design for how).
- **AC-9** Changing an object a function returned SHALL NOT change the cache.
- **AC-10** WHEN a request fails, THE SYSTEM SHALL leave the cache entry unchanged and let the error surface as before.
- **AC-11** Output SHALL follow ADR-0004 exactly as uncached output does: YNAB's property names, converted amounts, `*_currency` removed, deleted items left out.

### Life cycle

- **AC-12** The cache SHALL live only in module memory. THE SYSTEM SHALL NOT write cached data to disk.
- **AC-13** `Disconnect-Ynab` SHALL clear the whole cache. A successful `Connect-Ynab` SHALL also clear it, since a new token may belong to a different YNAB user.
- **AC-14** A new exported function, `Clear-YnabCache`, SHALL clear the whole cache, or only one plan's entries with `-PlanId`.

### Module

- **AC-15** New and changed functions SHALL have comment-based help and tests that never reach the network. Help for each cached function SHALL say that results are cached for the session and how to clear them. CI SHALL pass, with the `min-tests` floor re-derived per AGENTS.md.

## Out of scope

- Persisting the cache or server knowledge across sessions, by the module or by the caller.
- Answering calls from the cache without a request (unless open question 1 decides otherwise).
- Caching single-item calls, and new functions for scheduled transactions, money movements, or per-payee and per-month transaction lists.

## Resolved questions

- **No request-free answers from the cache.** A short expiry would answer repeated calls without a request, saving rate-limit budget at the cost of stale results. Rejected: every call sends one delta request and is always current (AC-7); a daily alerter is nowhere near the limit, and interactive use rarely is.
- **`-IncludeDeleted` is not added.** It was moved here from step 2 because deleted items only appear in delta responses. With a merged cache, a deleted item is removed from the entry (AC-5), so the switch could only show items deleted since the session's first call for that list, a set that depends on when the session started. Nothing planned needs deleted items. Adding the switch later is not a breaking change, since existing calls and the default of leaving deleted items out stay the same; revisit it if caller-held server knowledge is ever added, where "what was deleted since my last sync" is a meaningful question.

## Open questions

None.

## Unverified, to settle with a live check during implementation

- How a delta request combines with `since_date`, `until_date` or `type` on the transaction endpoints: whether changes are filtered to the same range and type.
- How a delta response for categories is shaped: whether a changed category arrives inside its group with only the changed categories, or with the whole group.
