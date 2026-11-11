# ADR 2: Follow the YNAB Plans Naming

## Status

Proposed — 2026-11-10

## Context

- The YNAB API docs state that all endpoints now use `/plans/{plan_id}` as the primary resource path, and that the `/budgets/{budget_id}` paths continue to work for backward compatibility (changelog v1.79.0).
- The two path families return different response keys: `/budgets` paths keep the original names, while `GET /plans` returns `data.plans` and `data.default_plan`.
- The OpenAPI spec (v1.90.0) documents `/plans` paths; the `plan_id` parameter accepts `last-used`, and `default` when default plan selection is enabled.
- `Posh-YNAB` and most existing community examples predate the rename and use "budget" names, so users arriving from them know the old terms.
- `PS.YNAB` is at 0.1.0 with no exported functions, so choosing names now breaks no existing caller.
- "Budget" still has a second meaning in the API: the amount assigned to a category in a month (`budgeted`), which is unrelated to the plan container.

## Decision

- We will call only `/plans/{plan_id}` paths and parse the `plans` response keys.
- We will use "Plan" in function and parameter names that refer to the container: `Get-YnabPlan`, `-PlanId`.
- We will not add `Budget`-named aliases for those functions or parameters.
- We will keep "Budget" where it means the assigned amount, as in `Set-YnabCategoryBudget`.

## Consequences

- **Positive** — the module builds on the paths YNAB documents today, not on paths kept only for backward compatibility.
- **Positive** — one set of response keys to parse; no translation between `budgets` and `plans` shapes.
- **Negative** — users who know YNAB's API as "budgets", including from `Posh-YNAB`, must learn the new names, and examples written for the old API do not map one-to-one.
- **Negative** — with no aliases, a user who types `-BudgetId` gets a parameter-binding error instead of a redirect to `-PlanId`.
- **Neutral** — "Budget" survives in function names where it means an assigned amount, so the word alone does not tell a reader which meaning is in use.
