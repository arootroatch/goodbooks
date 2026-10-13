# goodbooks — Build Roadmap

The program-level view: what gets built, in what order, and what blocks what.

This is the canonical list of sub-projects. The overall design is
[`superpowers/specs/2026-10-05-goodbooks-design.md`](superpowers/specs/2026-10-05-goodbooks-design.md);
a sub-project that needed more design than its section there gets its own spec in
`docs/superpowers/specs/`. Implementation plans live in `docs/superpowers/plans/`. Progress is
also tracked in Kaneo (project GoodBooks, workspace Root User Projects).

**Target:** a self-hosted replacement for the parts of QuickBooks the household actually uses —
see the design spec's [success criteria](superpowers/specs/2026-10-05-goodbooks-design.md#success-criteria).

---

## Sub-projects

Each gets its own plan → implementation → PR cycle. "Size" is the task count of the
implementation plan, or blank before one exists.

| # | Sub-project | Contents | Design | Kaneo | Size | Status |
|---|---|---|---|---|---|---|
| 1 | **Core** | auth + mandatory TOTP 2FA, household / people / businesses / memberships, invite links, manual and CSV accounts, transactions, categories, rules + inbox, mileage, reports, backups, demo seed, Docker | [§5](superpowers/specs/2026-10-05-goodbooks-design.md#5-sub-project-1-core) | GB-2, GB-8 | 21 | Merged |
| 2 | **Invoices** | clients, invoice tracking (not generation), payments linked to deposits, inbox "Mark paid" hint, aging, PDFs, CSV; the CI `test` job and the Brakeman fix | [§6](superpowers/specs/2026-10-05-goodbooks-design.md#6-sub-project-2-invoices), refined by [its own spec](superpowers/specs/2026-10-06-goodbooks-invoices-design.md) | GB-3 | 15 | Merged |
| 3 | **Personal book + tithing** | the household's personal book (a `Business` with `kind: "personal"`), weekly tithe ledger, spending report, personal-book exclusion from every business-only path | [own spec](superpowers/specs/2026-10-06-goodbooks-tithing-design.md) (inserted in [§4](superpowers/specs/2026-10-05-goodbooks-design.md#4-decomposition)) | GB-9 | 10 | Merged |
| 4 | **Sales tax (Tennessee)** | per-business profile, taxable/exempt treatment on income categories, Stripe processor fees, collected tax kept out of income, filing periods and remittances, period report, dashboard due card | [own spec](superpowers/specs/2026-10-08-goodbooks-sales-tax-design.md) | GB-4 | 15 | Merged |
| 5 | **Plaid** | Link + token exchange, account assignment to any owned book (new or attach to existing), CSV ↔ Plaid dedup by claiming, needs-review flags, `transactions/sync`, daily / webhook / manual sync job, re-link on `ITEM_LOGIN_REQUIRED`, verified webhooks, fake client | [own spec](superpowers/specs/2026-10-08-goodbooks-plaid-design.md) | GB-5 | 17 | Merged |
| 6 | **Tax engine** | federal MFJ quarterly estimates (SE tax, QBI, brackets, safe harbor vs annualized), home office, per-person adjustments, Schedule C line 30 | [own spec](superpowers/specs/2026-10-12-goodbooks-tax-engine-design.md) | GB-6 | 15 | In review (PR pending) |
| 7 | **Sharing polish** | SMTP invite delivery, session management, audit log | [§10](superpowers/specs/2026-10-05-goodbooks-design.md#10-sub-project-7-sharing-polish) | GB-7 | | Not started |
| 8 | **Goals** | payment goals (progress toward a target from payments matched to the goal, e.g. paying back a loan) and savings goals (target amounts filled in priority order from one account's balance), dashboard progress widget, per-goal report of contributing transactions; account balances as groundwork | [notes below](#goals-sub-project-8) | GB-11 | | Not started |

### Notes on the mapping

- **Numbers follow the design spec's [§4 Decomposition](superpowers/specs/2026-10-05-goodbooks-design.md#4-decomposition).**
  Sub-project numbers are not section numbers: the design spec describes sub-project 4 in §7,
  and so on. Sub-projects 4–7 were renumbered on 2026-10-08, after Personal book + tithing was
  inserted as 3 (old → current: Sales tax 3 → 4, Plaid 4 → 5, Tax engine 5 → 6, Sharing polish
  6 → 7). The implementation plans predate that and still use the old numbers.
- **Personal book + tithing is 3 because it was added after the first pass.** It was inserted
  after Invoices, before Sales tax ([tithing spec §9](superpowers/specs/2026-10-06-goodbooks-tithing-design.md#9-parent-spec-amendments)),
  and amends the parent spec's §1: an account now belongs to exactly one *book*, a business or
  the household's single personal book.
- **Invoices carried the "green CI" work.** Its spec's [§8](superpowers/specs/2026-10-06-goodbooks-invoices-design.md#8-ci-requirements)
  adds the RSpec job and fixes the Brakeman warning on `TransactionsController#filter_params`
  that keeps `main`'s `scan_ruby` red until PR #6 merges.
- **Goals (8) was added on 2026-10-12, after the first pass.** It sits off the critical path.
  Its requirements are captured [below](#goals-sub-project-8) until it gets its own spec.
- **Core's follow-ups (GB-8)** were a review-fix pass on `main` after Core landed, not a
  sub-project of their own.

---

## Dependency graph

```
✓ 1 Core
    └── ✓ 2 Invoices
            └── ✓ 3 Personal book + tithing
                    ├── ✓ 4 Sales tax ── ◐ 6 Tax engine ── ○ 7 Sharing polish
                    └── ✓ 5 Plaid ── ○ 8 Goals
```

✓ merged to `main` · ◐ PR open · ○ not started.

Read it as:

- **Personal book needs Invoices** because its exclusion work reaches into invoice code:
  `BusinessKindOnly` guards the clients, invoices, payments, PDF and aging controllers, and the
  household invoice list, aging and `InvoiceMatcher.for_businesses` all filter to business-kind
  books ([tithing spec §6](superpowers/specs/2026-10-06-goodbooks-tithing-design.md#6-authorization-and-exclusions)).
- **Sales tax needs Invoices** because invoiced sales carry `Invoice#sales_tax_cents`, which is
  pro-rated onto deposits when a payment is linked ([§7.2](superpowers/specs/2026-10-05-goodbooks-design.md#72-recording-collected-tax)).
  It needs Personal book because a sales tax profile belongs to a business, never the personal book.
- **Plaid needs Invoices** for the removed-transaction rule (below), and Personal book because
  the joint checking account it will feed lives there.
- **Tax engine needs Sales tax** because net profit is income *net of collected sales tax*
  ([tax engine spec §4.1](superpowers/specs/2026-10-12-goodbooks-tax-engine-design.md#41-inputs-taxinputsloadhousehold-year-tax_parameters-today-query)),
  and Personal book because tax estimates must not see personal activity.
- **Sharing polish comes last** because the audit log covers the records of every earlier
  sub-project: invoices, payments, sales tax periods and tax inputs ([§10](superpowers/specs/2026-10-05-goodbooks-design.md#10-sub-project-7-sharing-polish)).
  Email delivery and session management need only Core and could ship earlier on their own.

- **Goals needs Personal book** because its main users are household goals in the personal
  book. It needs Plaid for bank-reported balances, which savings goals read (manual and CSV
  accounts need a balance of their own; see the open questions below).

**Critical path:** `1 → 2 → 3 → 4 → 6 → 7`. Plaid and Goals are off it: once 3 merged, 4 and 5
could run side by side.

**Goals and Tax engine can run in parallel.** Neither depends on the other. The tax engine
excludes the personal book and works on its own tax inputs, payments and pages. Goals works on
accounts, transactions and the personal book. They overlap only on the dashboard view and
`db/schema.rb`, so whichever merges second rebases.

---

## Hand-offs

Obligations an earlier sub-project filed against a later one. They live here so they survive
the plan that found them.

- **4 Sales tax — hook invoice sales tax into `InvoicePayments#link`.** That is where a linked
  payment pro-rates the invoice's sales tax onto its deposit.
  ([invoices spec §9](superpowers/specs/2026-10-06-goodbooks-invoices-design.md#9-hand-offs-to-later-sub-projects))
- **4 Sales tax — keep the personal book out.** Sales tax screens and the dashboard due card
  use `Business.business_kind`, and new business-only controllers include `BusinessKindOnly`.
  ([tithing spec §6](superpowers/specs/2026-10-06-goodbooks-tithing-design.md#6-authorization-and-exclusions))
- **5 Plaid — flag, don't exclude, a removed transaction that has invoice payments**, the same
  way a categorized removed transaction is flagged for review.
  ([invoices spec §9](superpowers/specs/2026-10-06-goodbooks-invoices-design.md#9-hand-offs-to-later-sub-projects),
  [§8](superpowers/specs/2026-10-05-goodbooks-design.md#8-sub-project-5-plaid))
- **5 Plaid — allow linking Plaid accounts to the personal book.** The account-assignment step
  in §8 offers "one of their businesses"; the joint checking account belongs to the personal
  book. ([tithing spec, Out of scope](superpowers/specs/2026-10-06-goodbooks-tithing-design.md#out-of-scope))
- **6 Tax engine — exclude the personal book from every estimate.**
  ([tithing spec, Success criteria](superpowers/specs/2026-10-06-goodbooks-tithing-design.md#success-criteria) item 5)
  Covered by the [tax engine spec](superpowers/specs/2026-10-12-goodbooks-tax-engine-design.md) §4.1 and §6.1.
- **7 Sharing polish — the audit log covers invoices and invoice payments.**
  ([invoices spec §9](superpowers/specs/2026-10-06-goodbooks-invoices-design.md#9-hand-offs-to-later-sub-projects))

---

## Goals (sub-project 8)

Requirements as captured on 2026-10-12, before a spec exists. It's aimed at the personal book,
but it's built for every book because that's no harder.

**Use case A — a payment goal.** "We agreed to pay Uncle Tony $30,000." The goal has a target
amount. Payments to Tony are matched to it automatically, and the dashboard widget shows a
progress bar (e.g. $12,000 of $30,000). Clicking the widget opens a report listing every
transaction linked to the goal, with a running total.

**Use case B — savings goals that share one account, filled in priority order.** "Keep a $6,000
nest egg, and save $10,000 for a truck. Both live in the same savings account, and the nest egg
comes first." With $8,000 in the account, the widget shows the nest egg **met** ($6,000 of
$6,000) and the truck at $2,000 of $10,000. The balance fills the goals in order, like a
waterfall.

**Shape it suggests** (to confirm in the spec):

- A `Goal` belongs to a book and has a name, a target in cents, a kind (`payments` or
  `savings`), a position for priority, and optionally a target date and an archived/completed
  state.
- **Payment goals** sum the transactions linked to them. Links are set automatically by a
  matcher on the goal (payee contains "Tony", optionally limited to a category or an amount
  range, reusing the `Rule` field/operator vocabulary) and can be added or removed by hand from
  a transaction. The report is the list of linked transactions.
- **Savings goals** point at an account and read its balance. Goals on the same account are
  allocated by position: each takes `min(target, what's left)`. The report shows the
  account's deposits and withdrawals over time, alongside the allocation.
- A dashboard widget per book (the personal section for household members), plus a Goals page
  in the book's nav.

**Open questions for the spec:**

1. **Account balances don't exist yet.** `accounts` has no balance column, and a transaction
   sum alone is wrong without a starting point. Options: store the Plaid-reported balance on
   sync (`accounts/balance/get`, or the balances that come back with `transactions/sync`
   accounts), and give manual and CSV accounts an opening balance + date so the balance is
   opening + sum of later transactions. Probably both.
2. **Does a payment to Tony also count as an expense?** Repaying a loan is usually a transfer
   or a liability payment, not spending. Decide whether goal payments keep their category,
   or whether a "Loan repayment" category is needed. Either way the goal link should be
   independent of the category.
3. **Can one transaction count toward more than one payment goal?** Probably not. One link per
   transaction keeps the totals honest.
4. **Savings goals, money set aside vs. account balance.** The waterfall uses the live balance,
   so a withdrawal shrinks the lowest-priority goal first. Confirm that's the intended
   behavior, rather than "earmarked" contributions per goal.
5. **What happens when a goal is met?** Show it as met and keep it on the widget, or move it to
   a completed list. For savings, a met goal can become unmet again if the balance drops.
6. **Who sees goals?** Same rules as the book they belong to; viewers can see, editors can edit.

---

## Status convention

Update the Status column as work lands:

- **Not started** — no plan written
- **Specced** — a sub-project spec exists beyond the design spec's section
- **Planned** — implementation plan in `docs/superpowers/plans/`
- **In progress** — being built
- **In review (PR #N)** — PR open, CI green
- **Merged** — on `main`

When a sub-project reaches **In review**, change its `○` to `◐` in the dependency graph; when it
reaches **Merged**, change it to `✓`. Every node carries a mark, so swapping one never moves
the lines. Move the Kaneo task in the same change.

## Documents

| Sub-project | Spec | Plan |
|---|---|---|
| 1 Core | [design §1–§5](superpowers/specs/2026-10-05-goodbooks-design.md) | [Core](superpowers/plans/2026-10-05-goodbooks-core.md) |
| 2 Invoices | [design](superpowers/specs/2026-10-06-goodbooks-invoices-design.md) | [Invoices](superpowers/plans/2026-10-06-goodbooks-invoices.md) |
| 3 Personal book + tithing | [design](superpowers/specs/2026-10-06-goodbooks-tithing-design.md) | [Personal book + tithing](superpowers/plans/2026-10-06-goodbooks-tithing.md) |
| 4 Sales tax | [design](superpowers/specs/2026-10-08-goodbooks-sales-tax-design.md) | [Sales tax](superpowers/plans/2026-10-08-goodbooks-sales-tax.md) |
| 5 Plaid | [design](superpowers/specs/2026-10-08-goodbooks-plaid-design.md) | [Plaid](superpowers/plans/2026-10-08-goodbooks-plaid.md) |
| 6 Tax engine | [design](superpowers/specs/2026-10-12-goodbooks-tax-engine-design.md) | [Tax engine](superpowers/plans/2026-10-12-goodbooks-tax-engine.md) |
| 7 Sharing polish | [design §10](superpowers/specs/2026-10-05-goodbooks-design.md#10-sub-project-7-sharing-polish) | — |
| 8 Goals | [notes](#goals-sub-project-8) (needs a spec) | — |
