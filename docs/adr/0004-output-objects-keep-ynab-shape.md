# ADR 4: Output Objects Keep YNAB's Shape

## Status

Accepted — 2026-11-11

## Context

- Every read function returns objects parsed from YNAB's JSON, and the write functions planned in step 5 will return the objects YNAB sends back. Whatever shape these objects take, users and scripts will depend on it.
- YNAB names properties in snake_case (`category_group_name`, `cleared_balance`). PowerShell convention favors PascalCase property names.
- YNAB's API docs and OpenAPI spec describe objects by YNAB's property names, and YNAB adds properties over time.
- Amounts are whole-number milliunits (1000 = 1.00). The repository rule is that callers never see raw milliunit values.
- Newer responses also carry `<amount>_formatted` (display text in the plan's currency format) and `<amount>_currency` (the amount as a floating-point number) next to many amounts. Per the OpenAPI spec, the full plan's transactions, split transactions, months and categories carry neither.
- Per the OpenAPI spec, every object type with a `deleted` flag says deleted items "will only be included in delta requests".
- Accounts, categories, payees and transactions all have an `id` property, as plans do, so a parameter bound from the pipeline by `id` cannot tell a plan from an account.
- The OpenAPI spec defines 13 int64 amount fields and three account loan maps whose values are whole numbers, all with names that no non-amount field shares.

## Decision

- We will return YNAB's objects with YNAB's property names and casing, not mapped to PascalCase.
- We will convert every amount field from milliunits to `System.Decimal` in place, at any depth, including the values of the account loan maps.
- We will identify amount fields by name, from two lists kept as constants in `PS.YNAB.psm1`, and not by the presence of a `*_currency` companion.
- We will remove each `<amount>_currency` property and keep each `<amount>_formatted` property.
- We will drop items marked `deleted` from every list, at any depth. A switch to include them arrives with delta requests in step 3.
- We will add one property of our own: `plan_id`, equal to `id`, on plan objects, so plans can be piped into plan-scoped functions without any other object's `id` being taken for a plan ID.

## Consequences

- **Positive** — property names match YNAB's documentation exactly, so users can work from YNAB's docs, and new YNAB properties appear without module changes.
- **Positive** — amounts are exact decimals everywhere, so no caller divides by 1000 or meets a floating-point currency value.
- **Positive** — one helper and two lists implement the convention for every function, so new read and write functions inherit it for free.
- **Negative** — property names are snake_case, unlike most PowerShell objects, and tab completion and formatting show them that way.
- **Negative** — a new amount field YNAB adds passes through as raw milliunits until it is added to the list, and nothing reports the miss at runtime. A property-name audit against a live plan is the check.
- **Negative** — matching by name would wrongly convert a future non-amount field that reuses an amount field's name.
- **Negative** — the loan interest-rate map is converted like the other loan maps, but its unit is undocumented; if it is not in milliunits, its converted values are wrong.
- **Neutral** — `plan_id` is the one property not from YNAB, so it must not be mistaken for an API field.
- **Neutral** — the write functions in step 5 must send amounts in milliunits; this ADR covers only what functions return.
