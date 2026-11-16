# Delta cache: tasks

Implements [design.md](design.md). Two PRs, in order; each leaves the module importable with all tests passing. Check a box only after its verification has run and passed, in the same PR that completes the task. Both PRs reference [#21](https://github.com/jjohns-dev/PS.YNAB/issues/21); PR 2 closes it.

## Standard checks before each PR

The same checks as the [core-reads tasks](../core-reads/tasks.md#standard-checks-before-each-pr) (S1 to S5), plus:

- **S6** Re-derive the `min-tests` floor per AGENTS.md (Build and CI) from the PR run's `Pester Results` artifact, update `.github/workflows/ci.yml` with the executed count and arithmetic, and push. Verify: the PR's checks pass with the new floor.

## PR 1: cache machinery

- [x] **1.1** Write `docs/adr/0005-session-only-delta-cache.md` with status `Proposed`, covering the design's ADR check, and add the dated amendment note to ADR-0004's status, naming its `-IncludeDeleted` sentence.
  - Verify: ADR-0005 has the five sections and at least one negative consequence; ADR-0004's Context, Decision and Consequences are unchanged.
- [x] **1.2** Initialize `$script:YnabCache` in `PS.YNAB.psm1`.
  - Verify: the module imports, and `InModuleScope PS.YNAB { $script:YnabCache.Count }` returns 0.
- [x] **1.3** Add `Private/Merge-YnabDelta.ps1` and its tests, covering every case in the design's test list (AC-5).
  - Verify: `Invoke-Pester` on `Merge-YnabDelta.tests.ps1` passes.
- [x] **1.4** Extract `Private/ConvertTo-YnabQueryString.ps1` from `Invoke-YnabRequest`, with tests, so the cache key and request URI share one implementation (added while implementing). Add `Private/Invoke-YnabCachedRequest.ps1` and its tests, covering every case in the design's test list, including the verbose message for keyword plans and the AC-6 equivalence test (AC-3 to AC-12).
  - Verify: `Invoke-Pester` on `Invoke-YnabCachedRequest.tests.ps1` passes. Also run the copy test against a version that returns the entry without copying, in a scratch copy of the repo, and confirm it fails.
- [x] **1.5** Add `Public/Clear-YnabCache.ps1` and its tests, and export it: clears everything; `-PlanId` clears only that plan; a keyword plan ID is rejected at binding; nothing is written to the output (AC-14).
  - Verify: `Invoke-Pester` on `Clear-YnabCache.tests.ps1` passes.
- [x] **1.6** Clear the cache in `Connect-Ynab` after a token is accepted and in `Disconnect-Ynab`, with tests that a rejected token leaves the cache alone (AC-13).
  - Verify: `Invoke-Pester` on `Connect-Ynab.tests.ps1` and `Disconnect-Ynab.tests.ps1` passes.
- [x] **1.7** Standard checks S1 to S6. Before merge, push a final commit setting ADR-0005 to `Accepted`.
  - Verify: as in S1 to S6; ADR-0005 shows `Accepted` on `main` after merge.

## PR 2: use the cache

- [x] **2.1** Switch the list paths of `Get-YnabPlan`, `Get-YnabAccount`, `Get-YnabCategory`, `Get-YnabPayee`, `Get-YnabMonth` and `Get-YnabTransaction` (`_plan`, `_account`, `_category`) to `Invoke-YnabCachedRequest`, and add the caching paragraph to each one's help (AC-1, AC-2, AC-15).
  - Verify: each test file clears the cache in `BeforeEach` and passes, and has one new test showing a second call with a plan ID sends `last_knowledge_of_server` while single-item calls never do.
- [x] **2.2** Rewrite rule 6 in `docs/design.md` to describe the cache and link ADR-0005.
  - Verify: the rule no longer says caching is planned, and its links resolve.
- [x] **2.3** **You run the live check snippet** (provided in the PR) with your plan's ID. It prints only `True`/`False` per function for "cached result equals full result" and "second call sent knowledge", the item count each delta response carried, and the time each cached call took. No values, names or IDs.
  - Verify: every comparison is `True`. Any `False` is fixed before merge. The counts settle the two unverified delta shapes in the requirements, and the timings settle the design's copy-cost risk; both results are recorded here.
  - Result (2026-11-16): `CachedEqFull` and `SentKnowledge` were `True` for all six functions. Copy cost is not a concern: a cached `Get-YnabPlan` took 2069 ms against 2489 ms for a full download, and every other function was under 600 ms. Every delta carried 0 items because nothing changed in YNAB between calls, so the two delta shapes in the requirements remain unverified live; the merge handles either shape, and `Merge-YnabDelta`'s tests cover both.
  - **Correction:** "handles either shape" held for category groups but not for the transaction filters, where a delta can omit an item that leaves the filter. Targeted checks, with an edit made in YNAB between the two reads:
    - Categories, one Assigned amount changed: `EditSeen`, `SentKnowledge`, `CachedEqFull` all `True` (52 categories). Changed categories merge correctly.
    - `-SinceDate` 30 days, memo edited on an older transaction: `EditSeen` `False` (as expected), `CachedEqFull` `True` (89). Out-of-range changes do not leak in.
    - `-Type Uncategorized`, a test transaction categorized: `EditSeen` `True`, **`CachedEqFull` `False`**: `CountCached` 110 against `CountFull` 109. The delta reported the transaction as changed, not deleted, so it stayed in the cached list. Led to task 2.5.
- [x] **2.5** Stop caching `Get-YnabTransaction` in every form, record why as ADR-0006 amending ADR-0005, and update its help, design rule 6 and this spec (added after the live check).
  - Verify: `Get-YnabTransaction` tests show no form of the call caches, even with a plan ID; ADR-0006 is accepted before merge.
- [x] **2.4** Standard checks S1 to S6, with the PR body using `closes #21`.

## After the last merge

- [x] **3.1** Tick step 3 in issue #1's plan with links to #21 and both PRs, and tick this task in the next step's first PR.
  - Verify: issue #1 shows step 3 checked.
  - Result: done after #24 merged; #21 was closed by hand because #24 said `refs` instead of `closes`. This tick rides in the v0.2.0 version-bump PR.
