# goodbooks — Design System Spec

Date: 2026-10-10
Status: Draft for review

## 1. Purpose

goodbooks has no visual design: about 1KB of CSS and browser-default markup. The owner won't review the four open feature PRs (#6 invoices, #7 tithing, #8 sales tax, #9 plaid) until the app has a real look. This spec defines a design system and lands it as its own PR on `main`, ahead of that stack.

### Direction

Balanced: QuickBooks-style workflows with modern Vercel/Next.js polish, leaning toward data-driven accounting software. Dense, readable tables where data matters, more breathing room elsewhere.

### Success criteria

- Every existing page looks deliberate in light and dark mode without per-view rewrites.
- The four open PRs rebase onto this work with conflicts limited to `application.css` and the layout nav (a few lines each). Their views pick up the styles unchanged apart from deleting their `business_nav` lines.
- The business page becomes an overview with KPIs and two charts.
- No build step and no new gems. Propshaft + importmap stays the whole asset pipeline.
- Test suite stays green and test output stays clean.

## 2. Decisions

| Topic | Decision |
|---|---|
| Visual direction | "Ink & indigo": blue-tinted neutrals, indigo accent (Stripe/Mercury territory) |
| Color modes | Light + dark. Follows `prefers-color-scheme` by default; a System / Light / Dark toggle overrides it, stored in a cookie. |
| Navigation | Left sidebar with a business switcher. Drawer on narrow screens. |
| Typeface | IBM Plex Sans for UI, IBM Plex Mono for amounts. Self-hosted woff2. |
| CSS approach | Plain modern CSS with custom-property tokens. Plain elements are styled first; a small set of opt-in classes. |
| Charts | Server-rendered SVG from Ruby helpers. No chart JS. |
| Negative amounts | Parentheses, red: `($54.99)`. Applies to every on-screen amount. CSV exports keep `-54.99`. |
| Sequencing | Standalone PR on `main`, merged before the feature stack is rebased. |

## 3. Tokens

All tokens are CSS custom properties on `:root` in `tokens.css`. Components only ever reference tokens, never raw colors, so dark mode needs no component-level CSS.

Each color token is written once with both values using `light-dark(<light>, <dark>)`, so light and dark can never drift apart. Which value applies is driven by `color-scheme`:

- `:root { color-scheme: light dark; }`: System. Follows the OS.
- `:root[data-theme="light"] { color-scheme: light; }`: the user chose Light.
- `:root[data-theme="dark"] { color-scheme: dark; }`: the user chose Dark.
- Print forces `color-scheme: light`.

`light-dark()` is supported by every browser that `allow_browser versions: :modern` admits.

### Color

| Token | Light | Dark | Use |
|---|---|---|---|
| `--bg` | `#f6f7fb` | `#07080f` | Page background |
| `--surface` | `#ffffff` | `#0e1020` | Cards, tables, sidebar, inputs |
| `--hover` | `#f3f4f9` | `#141730` | Row and nav hover |
| `--fg` | `#0f1222` | `#e7e9f5` | Primary text |
| `--muted` | `#646a85` | `#9a9fbd` | Secondary text, table headers, axis labels |
| `--border` | `#e2e5ef` | `#1f2340` | Hairlines |
| `--border-strong` | `#cfd3e3` | `#2c3156` | Inputs, buttons, totals rule |
| `--accent` | `#4f46e5` | `#818cf8` | Primary buttons, links, active nav, income bars |
| `--accent-hover` | `#4338ca` | `#a5b4fc` | Primary button hover |
| `--accent-soft` | `#eef2ff` | `#1e1b4b` | Active nav background, neutral badges |
| `--accent-fg` | `#3730a3` | `#c7d2fe` | Text on `--accent-soft` |
| `--on-accent` | `#ffffff` | `#0e1020` | Text on `--accent` |
| `--ring` | `rgb(79 70 229 / .25)` | `rgb(129 140 248 / .35)` | Focus ring |
| `--neg` / `--neg-soft` | `#e11d48` / `#fff1f2` | `#fb7185` / `#2a0f1a` | Negative amounts, errors, danger |
| `--pos` / `--pos-soft` | `#0f9f6e` / `#ecfdf5` | `#34d399` / `#062a1e` | Positive net, success |
| `--warn` / `--warn-soft` | `#b45309` / `#fffbeb` | `#fbbf24` / `#2a1f05` | Warnings |
| `--chart-income` | `= --accent` | `= --accent` | Income series |
| `--chart-expense` | `#c7cbe0` | `#2e3358` | Expense series |
| `--chart-grid` | `#eceef5` | `#181b33` | Gridlines, bar tracks |

Text colors must meet WCAG AA (4.5:1) against `--bg` and `--surface` in both modes. This is checked during implementation and the values adjusted if needed.

### Type

- `--font-sans: "IBM Plex Sans", system-ui, sans-serif`
- `--font-mono: "IBM Plex Mono", ui-monospace, monospace`
- Weights shipped: Sans 400/500/600, Mono 400/500. Latin subset, woff2, `font-display: swap`.
- Scale: 11 (labels, table headers), 12.5 (dense UI), 13.5 (body), 16 (h3), 19 (h2/section), 22 (h1/page title). KPI figures 20–22, Mono.
- Headings use weight 600–650 and slight negative letter-spacing.

### Space, radius, shadow

- Spacing scale on a 4px base: `--space-1` (4) through `--space-8` (32).
- Radius: `--radius-sm` 6px (inputs, buttons), `--radius` 8px (cards, tables), `--radius-lg` 10px (drawer). Pills use 999px.
- Shadows used sparingly: drawer and dropdown only. Borders do the separating otherwise.

## 4. Base element styles (`base.css`)

Applied without classes, so existing and in-flight views are styled as written:

- `body`: `--bg`, `--fg`, sans 13.5px, line-height 1.5.
- `h1`–`h3`: the type scale above.
- `a`: `--accent`, no underline, underline on hover.
- `table`: full width, `--surface`, 1px `--border` with `--radius`. `th` uppercase 11px `--muted`. `tbody tr:hover` uses `--hover`. `tfoot td` bold with a `--border-strong` top rule.
- `.num` (already used ~42× in the PRs): right-aligned, Mono, tabular figures.
- `label`, `input`, `select`, `textarea`: block labels at weight 500. Inputs get `--border-strong`, `--radius-sm`, and a 3px `--ring` on focus. Rails' `.field_with_errors` wrapper turns the border `--neg`.
- `button`, `input[type=submit]`, and `button_to` forms: secondary style by default (surface + `--border-strong`).
- `.errors` (already used in the PRs): red error list in a `--neg-soft` box.
- Print: the existing `.no-print` keeps working. Print hides the sidebar and forces light colors.

## 5. Components (`components/*.css`)

Opt-in classes, kept deliberately few:

- **Buttons:** `.primary` (accent fill), `.danger` (red text), `.ghost` (no border). Default is secondary.
- **Flash:** `.flash.flash-notice` (green), `.flash.flash-alert` (red). These class names already exist in the layout.
- **Badge:** `.badge`, `.badge-pos`, `.badge-warn`, `.badge-neg`, `.badge-muted`. Used for categories and statuses.
- **Card:** `.card`: surface, border, radius, padding.
- **KPI tile:** `.kpi` with a `small` label, a Mono figure, and an optional `em` subtitle.
- **Page header:** `.page-header`: title and subtitle on the left, actions or controls on the right.
- **Segmented control:** `.segmented`: a row of links with one marked `aria-current="page"`.
- **Empty state:** `.empty`: dashed border, title, one line of text.
- **Charts:** `.chart`, plus `.hbar-list` for horizontal bar rows.

## 6. Layout and navigation

### Shell

`layouts/application.html.erb` becomes a two-column shell: sidebar and main. It is split into partials:

- `layouts/_sidebar.html.erb`
- `layouts/_business_switcher.html.erb`: a `<details>` dropdown listing the businesses the user can see. No JS.
- `layouts/_flash.html.erb`

### Sidebar contents

1. Business switcher, showing the current business, or "goodbooks" when no business is in context.
2. **Business section** (only when `@business` is set): Overview, Inbox (with uncategorized-count badge), Transactions, Accounts, Categories, Rules, Mileage. Then a **Reports** group: Profit & loss, Schedule C. Members appears only for owners, the same as today.
3. **Household section:** All businesses, Inbox (household), Household P&L, Tax parameters, Invites, People. Each keeps today's permission check verbatim.
4. Footer: current user's name, the theme toggle (section 6a), and the Sign out button.

The active link gets `aria-current="page"`, styled with `--accent-soft` / `--accent-fg`.

### Removing `business_nav`

The sidebar replaces the in-page business nav, so it is removed entirely in this PR, leaving no dead code:

- the `business_nav` helper in `ApplicationHelper`
- `app/views/businesses/_nav.html.erb`
- the `.business-nav` CSS rules
- all 24 `<%= business_nav @business %>` call sites on `main`

The feature PRs add their own call sites; those are deleted during each rebase (section 12).

### 6a. Theme toggle

- **Control:** a three-way segmented control in the sidebar footer: System / Light / Dark, with icons and accessible labels. On signed-out pages the same control sits below the card.
- **Storage:** a `theme` cookie (`system` | `light` | `dark`), one year, `SameSite=Lax`. Per device, no database column. A missing or unknown value means `system`.
- **Server render:** the layout sets `data-theme="light"` or `data-theme="dark"` on `<html>` from the cookie, and omits the attribute for `system`. The page therefore renders in the right theme on first paint, with no flash.
- **Client:** `theme_controller.js` (Stimulus) writes the cookie and updates `data-theme` immediately, without a reload. Each option is a `button_to` form that sends `PATCH /theme`. The controller intercepts the submit; with no JS the form submits normally, sets the cookie, and redirects back.
- **Endpoint:** `ThemesController#update` (`resource :theme, only: :update`). It accepts only the three known values, needs no authentication (it touches only a display cookie), and redirects to the referer or the root. It is CSRF-protected like every other form.
- Charts need nothing extra; they already read CSS variables.

### Narrow screens

Below 800px the sidebar becomes an off-canvas drawer opened by a menu button in a slim top bar. A small Stimulus controller (`sidebar_controller.js`) toggles it. This and `theme_controller.js` are the only new JavaScript.

### Signed-out pages

Sign-in, 2FA, 2FA setup, first-run setup, and invite acceptance render without the sidebar: a centered card on `--bg`, with the wordmark above it. The layout switches on `authenticated?`; no separate layout file unless that proves cleaner.

## 7. Money formatting

- The `money(cents)` helper returns negatives as `<span class="neg">($54.99)</span>` (HTML-safe) and positives as plain `$4,200.00`. `nil` stays `—`.
- `.neg` is red (`--neg`).
- `Money#to_s` is unchanged (`-$54.99`). It backs CSV exports and anything else that needs to stay parseable.
- Every view that already calls `money`, including the PRs', gets the new format without edits.

## 8. Business overview

`BusinessesController#show` becomes the overview.

### Period

- It includes `DateRangeParams`. The default range is year to date, as today.
- A segmented control in the page header links to Month (start of current month → today), Quarter (start of current quarter → today), and YTD. It sets `from`/`to`. A custom range from the URL is honored, and then no segment is marked current.

### Content, top to bottom

1. **Page header:** business name, "Taxpayer: <name>", period control.
2. **KPI tiles** (for the selected range): Income, Expenses, Net profit. Net is green when positive and red in parentheses when negative. Expenses has the subtitle "N% of income" (omitted when income is zero).
3. **Income vs expenses chart:** grouped monthly bars from January through the month of the range's end date, in that year. This is independent of the period control, so the trend stays meaningful when Month is selected. The current, incomplete month is drawn at reduced opacity. Includes a legend.
4. **Top expenses:** the top 5 expense categories in the selected range as horizontal bars, scaled to the largest. Shows an empty state when there are no expenses.
5. **Inbox preview:** the 3 oldest uncategorized transactions (date, payee, amount) with "Open inbox →" and the total count. Empty state "Inbox zero" when none.
6. **Accounts:** the current list of active accounts moves to a compact card at the bottom, with the owner's "Edit business" link.

### Data

- KPIs and top expenses come from `Reports::CategoryTotals.load(business_ids: [@business.id], range: date_range)`. Sums use the same rules the P&L uses (`Reports::ProfitAndLoss`), so the overview and the P&L report always agree.
- New `Reports::MonthlyTotals.load(business_ids:, year:, through_month:)` returns one row per month, with zero-filled income and expense cents, from one grouped query over `Transaction.countable`.

## 9. Charts (`app/helpers/charts_helper.rb`)

- `bar_chart(labels:, series:, label:, faded_last: false)`: grouped vertical bars. `series` is an ordered list of `{ key:, name:, values: }` (values in cents); `key` selects the CSS class `bar-<key>`, which maps to a `--chart-*` token. The y-axis rounds the maximum up to a nice number (1, 2, 5 or 10 × a power of ten) and draws gridlines at 0, ¼, ½, ¾ and the max, with compact dollar labels ($20k). Month abbreviations sit on the x-axis.
- `hbar_list(rows)`: rows of `{ label:, cents: }`, scaled to the max, with the amount in Mono.
- Output is an inline `<svg viewBox=…>` that scales to its container width. Fills come from CSS classes using `var(--chart-*)`, so the theme applies automatically.
- Accessibility: `role="img"` and an `aria-label` summary on the SVG, plus a `<title>` on every bar (for example "Mar income: $13,200.00").
- Edge cases: all-zero or empty data renders axes with no bars and no division by zero. Negative monthly net is not charted. Income and expense are both drawn as positive magnitudes.

## 10. Files

New:
- `app/assets/stylesheets/{tokens,fonts,base,layout}.css`
- `app/assets/stylesheets/components/{buttons,flash,badge,card,kpi,page_header,segmented,empty,chart}.css`
- `app/assets/fonts/` (Plex woff2 files and the OFL license)
- `app/views/layouts/{_sidebar,_business_switcher,_flash}.html.erb`
- `app/helpers/charts_helper.rb`
- `app/models/reports/monthly_totals.rb`
- `app/javascript/controllers/{sidebar,theme}_controller.js`
- `app/controllers/themes_controller.rb`

Changed:
- `app/views/layouts/application.html.erb`
- `app/assets/stylesheets/application.css` (reduced to anything not moved into the new files)
- `app/helpers/application_helper.rb` (`money` changes; `business_nav` removed)
- `config/routes.rb` (`resource :theme`)
- The 24 views that call `business_nav` (that line removed)
- `app/controllers/businesses_controller.rb`
- `app/views/businesses/show.html.erb`

Deleted:
- `app/views/businesses/_nav.html.erb`

## 11. Testing

TDD throughout, with one failing test at a time.

- **Helper specs:** `money` (negative, positive, zero, nil, HTML safety). `ChartsHelper`: bar count, bar heights proportional to values, labels, `<title>` text, `aria-label`, zero and empty data, faded last month.
- **Model specs:** `Reports::MonthlyTotals` zero-fills months, separates income from expense, excludes uncountable and other businesses' transactions, and respects `through_month`.
- **Request specs:**
  - Overview: shows KPIs, charts, top expenses, inbox preview and empty states. The period control sets the range and marks the current segment.
  - Sidebar: business section appears only with a business in context. Every role-gated link stays hidden from roles that can't see it today (mirror the existing nav conditions).
  - Signed-out pages render without the sidebar.
  - Theme: the `theme` cookie maps to `data-theme` on `<html>` (light, dark, absent for system or garbage). `PATCH /theme` sets the cookie for valid values, ignores invalid ones, and redirects back, signed in or out.
  - No page renders the old in-page business nav.
- **System specs (`js: true`):** at a narrow viewport, the menu button opens and closes the drawer. Choosing Dark in the toggle switches `data-theme` without a reload and survives a page visit.
- **Existing suite** stays green. Specs that asserted the old `-$` text on screen are updated to the parentheses format.
- **Visual check:** run the app with demo seed data and screenshot the overview, inbox, transactions, P&L, a form, and sign-in, in light and dark, before declaring done.

## 12. Rebasing the feature stack (after merge)

Stack: `main` ← #6 invoices ← #7 tithing ← (#8 sales-tax, #9 plaid).

1. Rebase #6 onto the new `main`. Resolve `application.css`: move its ~7 lines into the right component file. Resolve the layout nav: move its new links into `_sidebar.html.erb` under Household. Delete the `business_nav` calls in the PR's own views (about 9 in #6, a few in each later PR); any missed call raises `NoMethodError` in that PR's request specs.
2. Rebase #7 onto #6, then #8 and #9 onto #7, the same way.
3. Each PR's own views need no changes to be styled. Optional per-PR polish (page headers, badges for invoice status) is a separate small commit, not part of the rebase.

## 13. Out of scope

- Per-page redesigns beyond what element styles and the shell provide.
- Household-level overview charts.
- Interactive charts (zoom, crosshair).
