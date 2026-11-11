# Core reads: requirements

Step 2 of the plan in [#1](https://github.com/jjohns-dev/PS.YNAB/issues/1); tracked in [#6](https://github.com/jjohns-dev/PS.YNAB/issues/6). Constrained by [ADR-0002](../../adr/0002-follow-the-plans-naming.md) and [ADR-0003](../../adr/0003-session-token-auth-and-default-plan.md), and built on the [foundation](../foundation/) layer.

## Problem / motivation

`Connect-Ynab` can start a session, but nothing reads YNAB data yet. The spending-anomaly alerter needs transactions, categories and month budgets; interactive users need to look up plans, accounts and payees to find the IDs other commands take, and sometimes want a whole plan at once. Seven read functions cover that. They share most of their behavior (plan selection, amount conversion, output shape, deleted items), so the shared rules are specified once here, followed by what each function adds.

## User stories

- As a module user, I want to list my plans and their IDs, so that I can target a specific plan instead of `last-used`.
- As a module user, I want a whole plan in one object, so that I can inspect or export everything in it with one request.
- As a module user, I want to list or look up accounts, categories and payees, so that I can find the IDs and balances I need.
- As a module user, I want a month's budgeted, activity and balance figures per category, so that I can see where the plan stands.
- As a module user, I want to read transactions filtered by date, type, account or category, so that I can review spending.
- As a module user, I want every amount as a currency value, so that I never have to divide by 1000 myself.
- As a module user, I want to pipe a plan into the other read functions, so that I can work across plans without copying IDs.
- As the alerter's author, I want reads that send one request each, so that a daily run stays well inside 200 requests per hour.

## Acceptance criteria

IDs are stable: new criteria are added at the end of their group rather than renumbering.

### Shared: every read function

- **AC-1** Each call SHALL send exactly one request, through `Invoke-YnabRequest`.
- **AC-2** Every plan-scoped function SHALL have a `-PlanId` parameter that defaults to `last-used` and can be overridden with `$PSDefaultParameterValues` (ADR-0003).
- **AC-3** WHEN a plan object from `Get-YnabPlanList` is piped into a plan-scoped function, THE SYSTEM SHALL use that plan's ID.
- **AC-4** Every amount field in the output, including amounts nested in sub-objects such as a month's categories or a transaction's subtransactions, SHALL be a `System.Decimal` currency amount. No raw milliunit value SHALL reach the caller.
- **AC-5** Each function SHALL write one object per item to the pipeline, never a wrapper object or an array of items.
- **AC-6** WHEN a list contains items YNAB marks `deleted`, THE SYSTEM SHALL leave them out of the output.
- **AC-7** WHEN YNAB returns an error, THE SYSTEM SHALL let `Invoke-YnabRequest`'s error surface unchanged.
- **AC-8** No function SHALL expose a server-knowledge or delta parameter in this step, so step 3 can add caching without changing these parameters.
- **AC-9** Each function SHALL be exported, have comment-based help with a `.NOTES` `Status:` line, and have a `Tests/Unit/<Verb-Noun>.tests.ps1` that never reaches the network. CI SHALL pass.
- **AC-24** Parameters that cannot be used together SHALL be in separate parameter sets, so PowerShell rejects the combination at binding time, before the function runs or sends a request. This covers listing versus fetching one item by ID, `Get-YnabMonth`'s list versus a single month, and `Get-YnabTransaction`'s `-AccountId` versus `-CategoryId` and its filters versus a single transaction ID.
- **AC-25** Output objects SHALL keep YNAB's property names and casing (for example `category_group_name`, `cleared_balance`), with amounts converted in place.
- **AC-26** For each amount, the output SHALL keep YNAB's `<name>_formatted` display string and SHALL NOT include the `<name>_currency` floating-point copy.
- **AC-28** *Moved to step 3.* An `-IncludeDeleted` switch was planned here. YNAB's OpenAPI spec says deleted items of every type "will only be included in delta requests", and this step sends none (AC-8), so the switch would have no effect yet. Step 3 adds it with delta requests.

### `Get-YnabPlanList`

- **AC-10** WHEN called, THE SYSTEM SHALL return a summary of each plan the token can access (`GET /plans`), including its ID and name.

### `Get-YnabPlan`

- **AC-30** WHEN called, THE SYSTEM SHALL return the full plan for `-PlanId` (`GET /plans/{plan_id}`) as one object, including its accounts, payees, category groups, categories, months, transactions, subtransactions and scheduled transactions.
- **AC-31** THE SYSTEM SHALL leave deleted items out of each of the plan's nested lists, as well as its top level (AC-6).

### `Get-YnabAccount`

- **AC-11** WHEN called without an account ID, THE SYSTEM SHALL return the plan's accounts.
- **AC-12** WHEN called with an account ID, THE SYSTEM SHALL return that one account from the single-account endpoint.

### `Get-YnabCategory`

- **AC-13** WHEN called without a category ID, THE SYSTEM SHALL return the plan's categories as one object per category, each carrying its category group's ID and name, rather than as nested groups.
- **AC-14** WHEN called with a category ID, THE SYSTEM SHALL return that one category from the single-category endpoint.
- **AC-27** THE SYSTEM SHALL return hidden and internal categories (such as "Inflow: Ready to Assign") along with the rest; callers filter on their `hidden` and `internal` properties.

### `Get-YnabPayee`

- **AC-15** WHEN called without a payee ID, THE SYSTEM SHALL return the plan's payees.
- **AC-16** WHEN called with a payee ID, THE SYSTEM SHALL return that one payee from the single-payee endpoint.

### `Get-YnabMonth`

- **AC-17** WHEN called without a month, THE SYSTEM SHALL return a summary of each plan month.
- **AC-18** WHEN called with a month, THE SYSTEM SHALL return that month's detail, including its categories with budgeted, activity and balance amounts. The month SHALL be accepted as a date (any day in the month) or as `current`.

### `Get-YnabTransaction`

- **AC-19** WHEN called with no filters, THE SYSTEM SHALL return the plan's transactions, using YNAB's default date range (from one year ago).
- **AC-20** WHEN `-SinceDate` is given, THE SYSTEM SHALL return only transactions on or after that date.
- **AC-21** WHEN `-Type` is given as `Uncategorized` or `Unapproved`, THE SYSTEM SHALL return only transactions of that type.
- **AC-22** WHEN `-AccountId` or `-CategoryId` is given, THE SYSTEM SHALL use that account's or category's transactions endpoint. The two SHALL NOT be accepted together.
- **AC-23** WHEN called with a transaction ID, THE SYSTEM SHALL return that one transaction from the single-transaction endpoint.
- **AC-29** WHEN `-UntilDate` is given, THE SYSTEM SHALL return only transactions on or before that date. `-SinceDate` and `-UntilDate` SHALL be usable together, and map to the API's `since_date` and `until_date`.

## Out of scope

- Delta requests and lookup caching, and the `-IncludeDeleted` switch that goes with them: step 3.
- Separate functions for scheduled transactions, payee locations and money movements. Scheduled transactions still appear inside `Get-YnabPlan`'s output.
- A category's figures for one specific month (`GET /plans/{plan_id}/months/{month}/categories/{category_id}`); `Get-YnabMonth -Month` covers a month's categories.
- Write functions: step 5.

## Resolved questions

- **Output shape:** keep YNAB's property names and casing, converting amounts in place (AC-25). Mapping to PascalCase would need a per-schema map that drifts from YNAB's docs. Likely promoted to an ADR during design, since the write functions will share it.
- **`*_formatted` and `*_currency` companions:** keep `*_formatted` as display text; drop `*_currency`, an imprecise floating-point duplicate of the converted amount (AC-26).
- **Hidden and internal categories:** returned, with their `hidden` and `internal` flags (AC-27).
- **Mutually exclusive parameters:** enforced by parameter sets (AC-24).
- **Deleted items:** always left out (AC-6). The `-IncludeDeleted` switch moves to step 3 (AC-28): YNAB's OpenAPI spec says, for every object type with a `deleted` flag, that deleted items "will only be included in delta requests", so in this step the switch would never change the output. AC-6's filter stays as a cheap guard in case the docs are wrong, and step 3 needs it once delta responses arrive.
- **Transaction date range:** `-SinceDate` and `-UntilDate`, the API's `since_date` and `until_date` in PowerShell casing, so the names stay recognizable to anyone who knows the API (AC-20, AC-29). Payee and month filtering stay out.
- **Plans:** two functions, one per endpoint. `Get-YnabPlanList` wraps `GET /plans` (AC-10); `Get-YnabPlan` wraps `GET /plans/{plan_id}`, using `-PlanId` like every other plan-scoped function (AC-2, AC-30). This follows the `Get-<Noun>List` pattern AWS.Tools uses for list commands.
- **Amount conversion in `Get-YnabPlan`:** converted like every other function (AC-4), in step 2. Skipping conversion and keeping `*_currency` was considered and rejected: per the OpenAPI spec, the full plan's transactions, subtransactions, months and categories use schemas with no `*_currency` fields, so those amounts would have been raw milliunits only, against the repository rule that callers never see raw milliunits.

## Open questions

None.
