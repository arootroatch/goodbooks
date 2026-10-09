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
| 2 | **Invoices** | clients, invoice tracking (not generation), payments linked to deposits, inbox "Mark paid" hint, aging, PDFs, CSV; the CI `test` job and the Brakeman fix | [§6](superpowers/specs/2026-10-05-goodbooks-design.md#6-sub-project-2-invoices), refined by [its own spec](superpowers/specs/2026-10-06-goodbooks-invoices-design.md) | GB-3 | 15 | In review (PR #6) |
| 3 | **Personal book + tithing** | the household's personal book (a `Business` with `kind: "personal"`), weekly tithe ledger, spending report, personal-book exclusion from every business-only path | [own spec](superpowers/specs/2026-10-06-goodbooks-tithing-design.md) (inserted in [§4](superpowers/specs/2026-10-05-goodbooks-design.md#4-decomposition)) | GB-9 | 10 | In review (PR #7, stacked on #6) |
| 4 | **Sales tax (Tennessee)** | per-business profile, sales channels on income, collected tax kept out of income, filing periods and remittances, period report, dashboard due card | [§7](superpowers/specs/2026-10-05-goodbooks-design.md#7-sub-project-4-sales-tax-tennessee) | GB-4 | 15 | In review (PR #8) |
| 5 | **Plaid** | Link + token exchange, account assignment to any owned book (new or attach to existing), CSV ↔ Plaid dedup by claiming, needs-review flags, `transactions/sync`, daily / webhook / manual sync job, re-link on `ITEM_LOGIN_REQUIRED`, verified webhooks, fake client | [own spec](superpowers/specs/2026-10-08-goodbooks-plaid-design.md) | GB-5 | 17 | In review (PR #9) |
| 6 | **Tax engine** | federal MFJ quarterly estimates (SE tax, QBI, brackets, safe harbor vs annualized), home office, per-person adjustments, Schedule C line 30 | [§9](superpowers/specs/2026-10-05-goodbooks-design.md#9-sub-project-6-tax-engine-federal-mfj-sole-proprietors) | GB-6 | | Not started |
| 7 | **Sharing polish** | SMTP invite delivery, session management, audit log | [§10](superpowers/specs/2026-10-05-goodbooks-design.md#10-sub-project-7-sharing-polish) | GB-7 | | Not started |

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
- **Core's follow-ups (GB-8)** were a review-fix pass on `main` after Core landed, not a
  sub-project of their own.

---

## Dependency graph

```
✓ 1 Core
    └── ◐ 2 Invoices
            └── ◐ 3 Personal book + tithing
                    ├── ◐ 4 Sales tax ── ○ 6 Tax engine ── ○ 7 Sharing polish
                    └── ◐ 5 Plaid
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
  ([§9.2](superpowers/specs/2026-10-05-goodbooks-design.md#92-calculation-taxestimator-pure) step 1),
  and Personal book because tax estimates must not see personal activity.
- **Sharing polish comes last** because the audit log covers the records of every earlier
  sub-project: invoices, payments, sales tax periods and tax inputs ([§10](superpowers/specs/2026-10-05-goodbooks-design.md#10-sub-project-7-sharing-polish)).
  Email delivery and session management need only Core and could ship earlier on their own.

**Critical path:** `1 → 2 → 3 → 4 → 6 → 7`. Plaid is the only sub-project off it: once 3
merges, 4 and 5 can run side by side.

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
- **7 Sharing polish — the audit log covers invoices and invoice payments.**
  ([invoices spec §9](superpowers/specs/2026-10-06-goodbooks-invoices-design.md#9-hand-offs-to-later-sub-projects))

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
| 4 Sales tax | [design §7](superpowers/specs/2026-10-05-goodbooks-design.md#7-sub-project-4-sales-tax-tennessee) | — |
| 5 Plaid | [design](superpowers/specs/2026-10-08-goodbooks-plaid-design.md) | [Plaid](superpowers/plans/2026-10-08-goodbooks-plaid.md) |
| 6 Tax engine | [design §9](superpowers/specs/2026-10-05-goodbooks-design.md#9-sub-project-6-tax-engine-federal-mfj-sole-proprietors) | — |
| 7 Sharing polish | [design §10](superpowers/specs/2026-10-05-goodbooks-design.md#10-sub-project-7-sharing-polish) | — |
