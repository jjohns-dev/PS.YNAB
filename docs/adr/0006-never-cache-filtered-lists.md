# ADR 6: Never Cache Filtered Lists

Amends: ADR-0005

## Status

Accepted — 2026-11-16

## Context

- ADR-0005 caches list results for the session and keeps them current by merging YNAB delta responses. The merge removes an item only when the delta marks it `deleted`.
- Every transaction endpoint returns a filtered list: by date (YNAB applies a one-year window when no `since_date` is given, per its API docs), by `type`, by account or by category. Accounts, categories, payees, months and the full plan have no filter, so their items leave only by being deleted.
- A transaction can stop matching a filter without being deleted: it can be categorized or approved, have its date edited out of the range, or be moved to another account or category.
- A live check on 2026-11-16 against the maintainer's plan, using `Get-YnabTransaction -Type Uncategorized`: after one transaction was categorized, a full read returned 109 transactions, but the cached read still returned 110. The delta reported the categorized transaction as changed, not deleted, so the merge kept it. The same check found that a delta does respect `since_date` for changes outside the range (nothing leaked in), and that categories merge correctly.
- The date, account and category cases were not run live; they are inferred to behave like `type`, since none of them deletes the transaction.
- Keeping filtered lists cached would mean re-applying each filter to the merged result locally, which requires matching YNAB's exact definitions. "Uncategorized" already includes items the maintainer could not account for (109 for a plan with every transaction approved), so a local copy of that rule could silently disagree with YNAB.
- Re-downloading a filtered transaction list is cheap in practice: a 30-day list took about 230 ms in the live check.

## Decision

- We will not cache any list whose membership YNAB filters, because a delta response does not report an item that stops matching the filter.
- We will therefore not cache `Get-YnabTransaction` in any form; every call downloads its list in full.
- We will keep caching, under ADR-0005, the unfiltered lists: `Get-YnabPlan` and the list forms of `Get-YnabAccount`, `Get-YnabCategory`, `Get-YnabPayee` and `Get-YnabMonth`.
- We will apply the same test to every list added later: cache it only if its items can leave it solely by deletion.

## Consequences

- **Positive** — every transaction read is correct for its filter, with no local re-implementation of YNAB's filter rules.
- **Positive** — the rule is a single test any future list can be checked against.
- **Negative** — repeated transaction reads in a session download the full list each time, which costs more for long, unfiltered histories.
- **Negative** — ADR-0005's statement that long transaction lists benefit from caching no longer holds; only `Get-YnabPlan` caches transaction history, in YNAB's summary shape without names such as `account_name`.
- **Neutral** — if a future YNAB release reports filter departures in deltas, this decision can be revisited with a live check like the one above.
