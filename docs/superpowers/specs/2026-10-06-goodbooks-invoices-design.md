# goodbooks Invoices (Sub-project 2) — Design Spec

Date: 2026-10-06
Status: Draft for review
Parent spec: `2026-10-05-goodbooks-design.md` §6 (this document refines and supersedes it). The parent's cross-cutting rules (§3: money, sign convention, authorization, seeds, testing) apply unchanged.

## 1. Purpose

Track what clients owe each business and connect each payment to the deposit that paid it. Invoices are made and sent in another tool; goodbooks records them, optionally stores the PDF, and answers "who owes us what, and how late is it?"

Cash basis: invoices never count as income. Income comes only from categorized deposits, exactly as in Core.

### Understanding from the owner

- Clients nearly always pay one invoice with one deposit for the exact amount (check or ACH). The UI is built around fast 1:1 exact-amount matching. The data model still allows one deposit to pay several invoices and partial payments, but no processor-fee handling.
- Rules auto-categorize many deposits (e.g. "payee contains ACME → Gross receipts"), so those never reach the inbox. Linking must therefore work from the invoice side as well as from the inbox.

### Success criteria

1. Editors can record clients and invoices, attach a PDF, and see each invoice's outstanding balance and status (draft, sent, partial, overdue, paid, void).
2. A payment is recorded by linking an invoice to a deposit, from either the invoice page or the inbox, in one click for exact-amount matches.
3. Invoice status follows payments automatically and can never contradict them.
4. Per-business and household invoice lists, an aging report, and CSV exports exist.
5. `demo:seed` shows every invoice state, including an inbox deposit that matches an open invoice.
6. **The PR that delivers this sub-project passes every CI check**: Brakeman, bundler-audit, importmap audit, RuboCop, and a new RSpec job (§8). The existing Brakeman failure on `main` is fixed as part of this work.

### Out of scope

Generating or sending invoices, recurring invoices, line items, client portals, processor-fee splitting, multiple currencies, and invoice sales tax (sub-project 3).

## 2. Data model

```
Client          business, name, email (nullable), notes (nullable), archived_at
                unique(business, name)
Invoice         business, client, number (string), issue_date, due_date, amount_cents (> 0),
                description (nullable), status: draft|sent|paid|void, paid_on (nullable),
                pdf (Active Storage, optional)
                unique(business, number); due_date >= issue_date
InvoicePayment  invoice, transaction (FK `transaction_id`), amount_cents (> 0)
                unique(invoice, transaction)
```

- `Invoice#client` must belong to the same business. `InvoicePayment#transaction` must belong to an account in the invoice's business.
- `Transaction has_many :invoice_payments` (restrict deletion, see §3.4).
- **Number default**: a new invoice's number field is prefilled with the business's highest invoice number whose trailing digits parse as an integer, incremented and keeping its prefix and zero-padding (`INV-0042` → `INV-0043`). With no prior invoices: `1001`. Always editable; uniqueness is per business.
- **Status default**: `sent`. `draft` means "not sent yet".
- PDF: content type `application/pdf` only, max 10 MB.

### Derived values (never stored)

- `paid_cents` = sum of the invoice's payments. `outstanding_cents` = `amount_cents − paid_cents`.
- **Open** = status `sent` (includes partial and overdue).
- **Partial** = `sent` and `paid_cents > 0`.
- **Overdue** = `sent` and `due_date < Date.current`. `days_past_due` = `Date.current − due_date` when overdue.
- A deposit's `allocated_cents` = sum of its invoice payments; `unallocated_cents` = `amount_cents − allocated_cents`.

## 3. Rules

### 3.1 Linkable deposits

A transaction can be linked to an invoice only if all of these hold:

- It belongs to an account in the invoice's business.
- `amount_cents > 0`, `transfer = false`, `excluded = false`.
- Its category is nil or an income category (`kind: income`).
- `unallocated_cents > 0`.

The invoice must have status `sent` and `outstanding_cents > 0`.

### 3.2 Allocation amounts

- The proposed amount = min(invoice `outstanding_cents`, deposit `unallocated_cents`).
- An editor may lower it (partial payment). It must be > 0 and ≤ both limits. Anything else is a validation error with a specific message.

### 3.3 Status transitions

| From | Event | To |
|---|---|---|
| draft | Mark sent | sent |
| sent | payments reach `amount_cents` | paid, `paid_on` = latest linked deposit `posted_on` |
| paid | a payment is unlinked | sent, `paid_on` = nil |
| draft or sent with no payments | Void | void |
| void | Reopen | sent |

- Drafts and void invoices cannot take payments.
- `paid` is set only by the payment service (§4), never by the form. Editing a `paid` invoice's amount upward (allowed, since it stays ≥ `paid_cents`) reverts it to `sent`; the invoice update path calls the same `Invoice#sync_payment_status!` the service uses, so there is one place that decides paid vs. sent.

### 3.4 Guards on linked records

- A transaction with invoice payments cannot be deleted, marked as a transfer, excluded, or recategorized into a non-income category or to nil. The error reads: "Linked to INV-1042 — unlink the payment first." This applies to the transaction form, the classification endpoint, and `RuleApplier` (which skips such rows; it already never overwrites user categorizations, and linking marks the deposit `categorized_by: user`).
- An invoice with payments cannot be voided or deleted, and its `amount_cents` cannot go below `paid_cents`.
- An invoice can be deleted only when it has no payments.
- Clients are archived, never deleted. Archived clients are hidden from pickers but keep their invoices.

### 3.5 Authorization

- Clients, invoices, payments: viewers read; editors and owners write (data, not settings).
- Household invoice list and household aging follow the household-screen rule (viewer on every business).
- The invoice PDF is served by `InvoicePdfsController#show` after the business access check, streamed with `send_data` (`disposition: :inline`, `type: application/pdf`). Active Storage public routes stay disabled, so no blob URL is ever exposed.
- Strong params never permit foreign-key keys (`*_id`). `client_id` and `transaction_id` are read from `params` and resolved through the business (`@business.clients.active.find(...)`, `Transaction.for_businesses(@business.id).find(...)`), which yields 404 for other businesses' records and keeps Brakeman clean.

## 4. Components

### Pure (no database)

- **`Invoices::Allocation`** — given plain integers (invoice amount, invoice paid, deposit amount, deposit allocated) and an optional requested amount, returns either `{ok: amount}` or `{error: reason}`. Owns §3.2.
- **`Invoices::NumberSuggester`** — given existing number strings, returns the next number (§2).
- **`Reports::InvoiceAging`** — given structs (number, client, due_date, outstanding_cents, business) and an as-of date, returns buckets `current` (not past due), `1–30`, `31–60`, `60+` days past due, each with its invoices and total, plus a grand total.

### Service

**`InvoicePayments`** with `link(invoice:, transaction:, amount_cents: nil, category: nil)` and `unlink(payment)`. Each runs in one DB transaction that locks the invoice row and the transaction row (`lock!`, same pattern as Core's C1/C6 fixes), then:

- `link`: checks §3.1, computes the amount with `Invoices::Allocation`, categorizes an uncategorized deposit (with `category` if given, else the business's Gross receipts category, see §5.3) as `categorized_by: user`, creates the payment, and calls `invoice.sync_payment_status!`.
- `unlink`: destroys the payment and calls `invoice.sync_payment_status!`. The deposit keeps its category.
- `Invoice#sync_payment_status!` is the only code that moves between `sent` and `paid`: `paid` with `paid_on` = latest linked deposit date when `outstanding_cents == 0`, otherwise `sent` with `paid_on` nil. It never touches `draft` or `void`.
- Both return a result object (success, or an error message for the flash).

`InvoicePayment` itself has no callbacks; model validations enforce amount > 0, same-business, and uniqueness as a backstop.

## 5. Screens and routes

```ruby
resources :businesses do
  resources :clients, except: %i[show destroy]          # archive via update
  resources :invoices do
    patch :mark_sent, :void, :reopen, on: :member
    resource :pdf, only: :show, controller: "invoice_pdfs"
    resources :payments, only: %i[new create destroy], controller: "invoice_payments"
  end
  get "reports/aging", to: "invoice_agings#show", as: :invoice_aging
end
scope "household", as: "household" do
  get "invoices", to: "household_invoices#show", as: :invoices
  get "aging",    to: "household_invoice_agings#show", as: :invoice_aging
end
```

### 5.1 Clients

List (active by default, "Show archived" toggle like accounts), new/edit form: name, email, notes, archive checkbox. The invoice form's client select includes "New client…", which reveals an inline name field and creates the client with the invoice.

### 5.2 Invoices

- **List** (business and household): filters for status (all, open, overdue, paid, draft, void), client, issue-date range (reusing `DateRangeParams` with an "all dates" default for this list). Columns: number, client, business (household only), issued, due, amount, paid, outstanding, status badge (draft / sent / partial / overdue / paid / void). Header totals: outstanding and overdue. Paginated like transactions. A CSV export with the same filters, written through `Reports::CsvSafe`.
- **Form**: client, number (prefilled §2), issue date (default today), due date (default issue + 30 days), amount, description, PDF, status (draft or sent on create).
- **Show**: details, PDF link, payments table (deposit date, account, payee, amount, Unlink button for editors), and action buttons: Mark sent, Void, Reopen, Record payment, Edit, Delete, each shown only when allowed by §3.
- **Record payment** (`payments#new`): lists linkable deposits (§3.1) in the business. First, exact matches where `unallocated_cents == outstanding_cents`, newest first. Then other linkable deposits posted within the last 90 days, newest first, with a from-date filter to search further back. Each row: date, account, payee, amount, unallocated, an amount field (prefilled per §3.2) and a Link button. Success redirects to the invoice with a notice.

### 5.3 Inbox hint

- `InboxesController` and `HouseholdInboxesController` load open invoices with `outstanding_cents > 0` for the businesses on screen in one query and index them by `[business_id, outstanding_cents]`.
- A positive inbox row whose amount equals a key shows, below the normal controls: `Matches INV-1042 · Acme · due Sep 30  [Mark paid]`. Up to 3 matching invoices are listed (oldest due first); rows with no match render exactly as today.
- **Mark paid** posts to `invoice_payments#create` with `transaction_id` and `from_inbox=1`. It categorizes into the business's Gross receipts category: the single active income category with `schedule_c_line == "1"`. If there are several, the hint renders a select of them next to the button; if there are none, the hint is replaced by a link to the invoice's Record payment page. On success the response is the same `turbo_stream.remove(transaction)` the inbox uses for categorization (HTML fallback: redirect back).

### 5.4 Aging report

Per business and household, as of today: the four buckets with totals and the invoices in each (number, client, business in household view, due date, days past due, outstanding). CSV export.

### 5.5 Dashboard and navigation

- The dashboard business list and the business page show "Outstanding $X · Overdue $Y" when non-zero (sent invoices only).
- Business navigation gains Invoices, Clients, and Aging (under reports). Household navigation gains Invoices and Aging (shown only to users who pass the household-screen rule).

## 6. Error handling

- All service and validation failures re-render or redirect with a specific flash message; nothing fails silently.
- A stale or concurrent link (deposit fully allocated by someone else between page load and click) returns the allocation error as a flash, not a 500.
- Records in other businesses are 404 (lookup through the business), never 403.
- Turbo requests from the inbox that fail return a `turbo_stream.replace` of the row with the error shown inline.

## 7. Testing

TDD throughout. Test output must stay clean.

- **Pure unit specs** (no DB): `Invoices::Allocation` (exact match, partial, deposit already partly allocated, request above either limit, zero/negative request), `Invoices::NumberSuggester` (prefixed, zero-padded, numeric only, non-numeric existing numbers ignored, empty), `Reports::InvoiceAging` (boundaries at 0, 1, 30, 31, 60, 61 days; household grouping; totals).
- **Service specs** for `InvoicePayments`: link marks paid with correct `paid_on`; link categorizes an uncategorized deposit as user; rejects draft, void, paid, negative deposit, transfer, excluded, expense-category deposit, other-business deposit, over-allocation; unlink reverts paid to sent; a concurrency spec showing two links racing for the same deposit cannot over-allocate it.
- **Model specs**: §3.4 guards (transaction destroy/recategorize/transfer/exclude blocked when linked; invoice void/delete/amount-reduction blocked), uniqueness of number per business, client and payment same-business validations, `RuleApplier` skips linked rows.
- **Request specs** for every new controller with the standard matrix: non-member → 404, viewer cannot write, editor can write, owner can do everything. Plus: household invoice and aging pages require access to every business; the PDF endpoint enforces business access; a `client_id`/`transaction_id` from another business → 404; CSV export neutralizes formula prefixes.
- **System specs**: Record payment (open invoice → link exact-match deposit → invoice shows Paid); inbox hint (`js: true`, headless Chrome, following the existing inbox spec): matching row shows the hint, Mark paid removes the row without a page reload, the invoice shows Paid.
- **Demo seed**: 3–4 clients per business; about 15 invoices covering paid (linked), partial, overdue in each aging bucket, current, one draft, one void; at least one uncategorized inbox deposit matching an open invoice exactly.

## 8. CI requirements

The PR for this sub-project must pass every check in `.github/workflows/ci.yml`. Two pre-existing problems are fixed in the same PR:

1. **Brakeman (currently failing on `main`)**: a high-confidence Mass Assignment warning on `TransactionsController#filter_params` (`params.permit(..., :account_id, :category_id, ...)`). These are list filters applied to an already business-scoped relation, not record attributes, so it is a false positive. Fix: rework the filter so `TransactionFilter` receives the business-scoped relation and resolves `account_id`/`category_id` through it, and so no `*_id` key goes through `permit` (e.g. read the filter keys from `params` individually as scalars). Add a request spec proving another business's `account_id` returns no rows. Only if a warning cannot be removed in code does it go into `config/brakeman.ignore` with a note explaining why. New code introduces no Brakeman warnings.
2. **bundler-audit** has not run since Brakeman started failing. It must pass; vulnerable gems are updated in the PR.
3. **No test job exists.** Add a `test` job to `ci.yml`: checkout, `ruby/setup-ruby` with bundler cache, Chrome available for headless system specs (the runner's preinstalled Chrome or `browser-actions/setup-chrome`), `bin/rails db:test:prepare`, `bundle exec rspec`. It must pass with clean output.

`importmap audit` and RuboCop keep passing.

## 9. Hand-offs to later sub-projects

- **Sub-project 3 (sales tax)** adds `Invoice#sales_tax_cents` and pro-rates it onto linked deposits; `InvoicePayments#link` is where that hook goes.
- **Sub-project 4 (Plaid)**: when sync reports a removed transaction that has invoice payments, flag it for review instead of excluding it (consistent with the parent spec's "categorized removed transaction" rule).
- **Sub-project 6 (audit log)** covers invoices and invoice payments (already listed in the parent spec §10).
