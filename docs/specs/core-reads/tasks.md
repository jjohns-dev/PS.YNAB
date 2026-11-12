# Core reads: tasks

Implements [design.md](design.md). Seven PRs, in order; each leaves the module importable with all tests passing. Check a box only after its verification has run and passed, in the same PR that completes the task. Every PR references [#6](https://github.com/jjohns-dev/PS.YNAB/issues/6) with `refs #6`; only PR 7 closes it.

## Standard checks before each PR

Every PR's last task points here. Run all of them on the PR branch:

- **S1** Full local build: `./Build/build.ps1 -ResolveDependency -TaskList Init`, then `./Build/build.ps1 -TaskList CombineFunctionsAndStage, Analyze, Test`, then `-TaskList Cleanup`. Verify: success, no analyzer findings.
- **S2** Analyzer over the test files, which the code-scanning workflow also checks: `Invoke-ScriptAnalyzer -Path ./Tests -Recurse`. Verify: 0 findings.
- **S3** `Invoke-RestMethod` still appears only in `Private/Invoke-YnabRequest.ps1`. Verify: a search of `Public/` and `Private/`.
- **S4** The PowerShell skill's pre-commit checklist over every new or changed `.ps1`. Verify: each item confirmed or fixed.
- **S5** Commit with `refs #6`, push, open the PR. Verify: all checks pass, including `validate / validate (ubuntu-latest)` and the PSScriptAnalyzer code scan with 0 alerts. Merge only on your go-ahead.

## PR 1: conventions, helper and `Get-YnabPlanList`

- [x] **1.1** Write `docs/adr/0004-output-objects-keep-ynab-shape.md` with status `Proposed`, covering the points in the design's ADR check.
  - Verify: the file has the five ADR sections and at least one negative consequence.
- [x] **1.2** Add `$ynab_amount_fields` and `$ynab_amount_map_fields` to `PS.YNAB.psm1` as `Constant` variables.
  - Verify: `Invoke-Pester -Path Tests/Unit/Module.tests.ps1` passes, and `InModuleScope PS.YNAB { $ynab_amount_fields.Count }` returns 13.
- [x] **1.3** Add `Private/ConvertFrom-YnabData.ps1` and its tests, covering every case in the design's test list (AC-4, AC-6, AC-26, AC-31).
  - Verify: `Invoke-Pester -Path Tests/Unit/ConvertFrom-YnabData.tests.ps1` passes. Also run the amount-conversion tests against a copy of the helper with conversion removed, in a scratch worktree so no source file is edited, and confirm they fail.
- [x] **1.4** Add `Public/Get-YnabPlanList.ps1` and its tests, and export it. Tests cover: one `GET /plans` call; one object per plan; `plan_id` equal to `id`; the output piped into a function with a pipeline-bound `-PlanId` (AC-1, AC-3, AC-5, AC-10).
  - Verify: `Invoke-Pester` on `Get-YnabPlanList.tests.ps1` and `Module.tests.ps1` passes.
- [x] **1.5** Tick task 6.2 in `docs/specs/foundation/tasks.md`, which was done after the foundation merge. Delete `Private/.gitkeep`, which is no longer needed now that `Private/` holds functions (added in review).
  - Verify: the file shows 6.2 checked; `Private/.gitkeep` is gone and the build still stages `Private/`.
- [x] **1.6** Standard checks S1–S5. Before merge, push a final commit setting ADR-0004 to `Accepted`.
  - Verify: as in S1–S5; ADR-0004 shows `Accepted` on `main` after merge.

## PR 2: `Get-YnabPlan`

- [x] **2.1** Add `Public/Get-YnabPlan.ps1` and its tests, and export it. Tests cover:
  - one `GET /plans/{plan_id}` call, defaulting to `last-used`, and taking `-PlanId` from `$PSDefaultParameterValues` and from a piped plan
  - one plan object with `plan_id` added
  - amounts converted inside every nested list: accounts, categories, months and their categories, transactions, split transactions, scheduled transactions
  - deleted items dropped from nested lists
  - (AC-1 to AC-5, AC-30, AC-31)
  - Verify: `Invoke-Pester` on `Get-YnabPlan.tests.ps1` passes.
- [x] **2.2** Standard checks S1–S5.

## PR 3: `Get-YnabAccount`

- [x] **3.1** Add `Public/Get-YnabAccount.ps1` and its tests, and export it. Tests cover:
  - `_list` calls `/accounts`; `_id` calls `/accounts/{account_id}`
  - balances and loan maps converted
  - `-AccountId` with an empty string is rejected
  - the plan pipeline binds, and a piped account object does not bind `-PlanId`
  - (AC-1 to AC-5, AC-11, AC-12, AC-24)
  - Verify: `Invoke-Pester` on `Get-YnabAccount.tests.ps1` passes.
- [x] **3.2** Standard checks S1–S5.

## PR 4: `Get-YnabCategory`

- [x] **4.1** Add `Public/Get-YnabCategory.ps1` and its tests, and export it. Tests cover:
  - `_list` flattens groups into one object per category, each keeping `category_group_id` and `category_group_name`
  - categories of a deleted group are dropped
  - hidden and internal categories are kept
  - `_id` calls `/categories/{category_id}`
  - budgeted, activity, balance and goal amounts converted
  - (AC-1 to AC-5, AC-13, AC-14, AC-24, AC-27)
  - Verify: `Invoke-Pester` on `Get-YnabCategory.tests.ps1` passes.
- [x] **4.2** Standard checks S1–S5.

## PR 5: `Get-YnabPayee`

- [ ] **5.1** Add `Public/Get-YnabPayee.ps1` and its tests, and export it. Tests cover: `_list` calls `/payees`; `_id` calls `/payees/{payee_id}`; one object per payee (AC-1 to AC-5, AC-15, AC-16, AC-24).
  - Verify: `Invoke-Pester` on `Get-YnabPayee.tests.ps1` passes.
- [ ] **5.2** Standard checks S1–S5.

## PR 6: `Get-YnabMonth`

- [ ] **6.1** Add `Public/Get-YnabMonth.ps1` and its tests, and export it. Tests cover:
  - `_list` calls `/months`
  - `-Month current` calls `/months/current`
  - `-Month '2026-11-15'` calls `/months/2026-11-01`
  - an invalid month string is rejected at binding
  - month and nested category amounts converted
  - (AC-1 to AC-5, AC-17, AC-18, AC-24)
  - Verify: `Invoke-Pester` on `Get-YnabMonth.tests.ps1` passes.
- [ ] **6.2** Standard checks S1–S5.

## PR 7: `Get-YnabTransaction`

- [ ] **7.1** Add `-Query` to `Private/Invoke-YnabRequest.ps1`, with tests:
  - the query string is built with sorted keys
  - values are URI-escaped
  - `$null` values are skipped
  - no `?` is added for an empty query
  - existing tests still pass
  - Verify: `Invoke-Pester` on `Invoke-YnabRequest.tests.ps1` passes.
- [ ] **7.2** Add `Public/Get-YnabTransaction.ps1` and its tests, and export it. Tests cover:
  - the endpoint each set calls
  - `since_date`, `until_date` and `type` in the query, formatted `yyyy-MM-dd` and lower-cased
  - `YnabInvalidDateRange` with no request sent
  - binding errors for `-AccountId` with `-CategoryId`, and for `-TransactionId` with a filter
  - amounts converted in transactions and their split parts
  - (AC-1 to AC-5, AC-19 to AC-24, AC-29)
  - Verify: `Invoke-Pester` on `Get-YnabTransaction.tests.ps1` passes.
- [ ] **7.3** **You run the live audit snippet** (provided in the PR) against your plan, with all seven functions on the branch. It prints property names only, never values.
  - Verify: it reports no `*_currency` properties, and no whole-number properties outside the amount list other than `server_knowledge` and known int32 fields. Any it does report are added to the list before merge.
- [ ] **7.4** *Optional, if you have a loan account:* compare one converted `debt_interest_rates` value with the rate shown in YNAB's app.
  - Verify: the values match, or the help text records the interest-rate unit as unverified.
- [ ] **7.5** Standard checks S1–S5, with the PR body using `closes #6`.

## After the last merge

- [ ] **8.1** Tick step 2 in issue #1's plan, with links to #6 and the seven PRs, and tick these spec tasks in the next step's first PR.
  - Verify: issue #1 shows step 2 checked.
