# Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give goodbooks a real visual design — ink & indigo tokens with light/dark/system themes, a sidebar shell, IBM Plex, element-first CSS, parenthesized negatives, and a business overview page with server-rendered SVG charts.

**Architecture:** Plain CSS files under `app/assets/stylesheets/` (Propshaft serves every file, alphabetically, via `stylesheet_link_tag :app`); color tokens use `light-dark()` driven by `color-scheme`, which a `theme` cookie overrides through `data-theme` on `<html>`. The layout becomes a sidebar shell for signed-in users and a centered card for signed-out pages. Charts are pure Ruby helpers emitting SVG; the overview reuses the P&L report classes plus one new monthly query.

**Tech Stack:** Rails 8.1, Ruby 4.0.7 (chruby), SQLite, Propshaft, importmap, Stimulus, Turbo, RSpec + Capybara (rack_test, and Selenium headless Chrome for `js: true`), FactoryBot.

**Spec:** `docs/superpowers/specs/2026-10-10-design-system-design.md`

## Global Constraints

- Ruby 4.0.7. Every shell command runs after `source /opt/homebrew/share/chruby/chruby.sh 2>/dev/null || source /usr/local/share/chruby/chruby.sh; chruby 4.0.7`. Abbreviated below as "with Ruby 4.0.7".
- No new gems, no npm packages, no CSS/JS build step. Propshaft + importmap only.
- TDD: write ONE failing test, watch it fail for the right reason, make it pass, repeat. Never edit production code before a failing test demands it (CSS and font files are exempt from unit tests but are covered by the asset spec in Task 2 and the visual check in Task 12).
- Test output must be clean: a passing run prints only RSpec's own output — no warnings, logs, or deprecations.
- `bundle exec rubocop` must stay clean (rubocop-rails-omakase). Double-quoted strings, `[ a, b ]` array spacing.
- Components reference tokens only — never raw hex colors outside `tokens.css`.
- Negative on-screen amounts render `($54.99)` in red; `Money#to_s` stays `-$54.99` (CSV exports depend on it).
- Theme cookie: name `theme`, values `system` | `light` | `dark`, 1 year, `SameSite=Lax`. Anything else means `system`.
- Breakpoint for the mobile drawer: `max-width: 800px`.
- Commit after each task. Message: imperative summary line, blank line, short body, then the trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Do not touch `Gemfile.lock` (Bundler 4 may add a `bundler` checksum line — `git checkout Gemfile.lock` if it appears).

## Review Focus

1. **A business with no transactions at all** — the overview must render 200 with `$0.00` KPIs, an empty chart (axes, no bars, no division by zero), and both empty states. Test in Task 10.
2. **Negative net profit** (expenses exceed income) — the Net KPI must show red parentheses and must not get the green `pos` class. Test in Task 10.
3. **A custom date range from the URL in a past year** (`?from=2025-01-01&to=2025-06-30`) — the chart covers Jan–Jun 2025, no month is faded, and no period segment is marked current. Test in Task 10.
4. **A tampered `theme` cookie** (`"><script>`, `blue`) — must be treated as `system`: no `data-theme` attribute, nothing echoed. Test in Task 3.
5. **A signed-in user with no memberships** (not a household viewer) — the sidebar renders without a business section and without household-only links, and the switcher shows no businesses, without raising. Test in Task 4.

---

## File Map

| File | Responsibility | Task |
|---|---|---|
| `app/helpers/application_helper.rb` | `money` (parentheses); `business_nav` removed | 1, 4 |
| `app/assets/fonts/*.woff2`, `app/assets/fonts/OFL.txt` | Self-hosted IBM Plex | 2 |
| `app/assets/stylesheets/tokens.css` | Color/type/space tokens, `color-scheme` switching | 2 |
| `app/assets/stylesheets/fonts.css` | `@font-face` | 2 |
| `app/assets/stylesheets/base.css` | Element styles: body, headings, links, tables, forms, buttons, `.num`, `.neg`/`.pos`, `.errors` | 2 |
| `app/assets/stylesheets/components/{buttons,flash,badge,card,empty}.css` | Opt-in components | 2 |
| `app/assets/stylesheets/application.css` | Misc app rules only (inline-form, drag handle) | 2, 4 |
| `app/models/theme.rb` | Theme choices + normalization | 3 |
| `app/helpers/theme_helper.rb` | `current_theme`, `theme_attribute` | 3 |
| `app/controllers/themes_controller.rb` + route | `PATCH /theme` | 3 |
| `app/views/layouts/application.html.erb` | Shell / auth layout switch, `data-theme` | 3, 4, 6 |
| `app/views/layouts/{_sidebar,_business_switcher,_flash}.html.erb` | Sidebar shell partials | 4 |
| `app/helpers/navigation_helper.rb` | `nav_link`, `business_inbox_count` | 4 |
| `app/assets/stylesheets/layout.css` | Shell, sidebar, auth layout, drawer, print | 4, 6 |
| `app/views/layouts/_theme_toggle.html.erb`, `app/javascript/controllers/theme_controller.js`, `components/segmented.css` | Theme toggle UI | 5 |
| `app/javascript/controllers/sidebar_controller.js` | Mobile drawer | 6 |
| `app/models/reports/monthly_totals.rb` | Monthly income/expense query | 7 |
| `app/helpers/charts_helper.rb`, `components/chart.css` | `bar_chart`, `hbar_list` | 8, 9 |
| `app/controllers/businesses_controller.rb`, `app/views/businesses/show.html.erb`, `app/helpers/overview_helper.rb`, `components/{kpi,page_header}.css` | Business overview | 10 |

---

### Task 1: Parenthesized negative amounts

**Files:**
- Modify: `app/helpers/application_helper.rb:2-4`
- Create: `spec/helpers/application_helper_spec.rb`

**Interfaces:**
- Produces: `money(cents) -> String` — `nil` → `"—"`; `>= 0` → `"$4,200.00"`; `< 0` → HTML-safe `<span class="neg">($54.99)</span>`.

- [ ] **Step 1: Run the existing suite to confirm a green baseline**

Run (with Ruby 4.0.7): `bundle exec rspec`
Expected: `0 failures`.

- [ ] **Step 2: Write the failing test**

```ruby
# spec/helpers/application_helper_spec.rb
require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#money" do
    it "wraps negatives in red parentheses" do
      expect(helper.money(-5_499)).to eq('<span class="neg">($54.99)</span>')
    end
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bundle exec rspec spec/helpers/application_helper_spec.rb`
Expected: FAIL — got `"-$54.99"`.

- [ ] **Step 4: Implement**

Replace the `money` method in `app/helpers/application_helper.rb` with:

```ruby
  def money(cents)
    return "—" if cents.nil?
    return Money.new(cents).to_s unless cents.negative?

    tag.span("(#{Money.new(-cents)})", class: "neg")
  end
```

- [ ] **Step 5: Run it to verify it passes**

Run: `bundle exec rspec spec/helpers/application_helper_spec.rb` → PASS.

- [ ] **Step 6: Add the remaining cases, one at a time, each run before moving on** (they should pass immediately; if one fails, fix the implementation)

```ruby
    it "returns HTML-safe output for negatives" do
      expect(helper.money(-1)).to be_html_safe
    end

    it "leaves positives and zero plain" do
      expect(helper.money(420_000)).to eq("$4,200.00")
      expect(helper.money(0)).to eq("$0.00")
    end

    it "shows a dash for nil" do
      expect(helper.money(nil)).to eq("—")
    end
```

- [ ] **Step 7: Run the full suite**

Run: `bundle exec rspec`
Expected: `0 failures`. If a request spec asserted on `-$` in a page body, update that expectation to the `($…)` form (CSV specs must NOT change).

- [ ] **Step 8: Commit**

```bash
git add app/helpers/application_helper.rb spec/helpers/application_helper_spec.rb
git commit -m "Show negative amounts in red parentheses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Tokens, fonts, base element styles, core components

**Files:**
- Create: `app/assets/fonts/IBMPlexSans-{Regular,Medium,SemiBold}-Latin1.woff2`, `app/assets/fonts/IBMPlexMono-{Regular,Medium}-Latin1.woff2`, `app/assets/fonts/OFL.txt`
- Create: `app/assets/stylesheets/{tokens,fonts,base}.css`
- Create: `app/assets/stylesheets/components/{buttons,flash,badge,card,empty}.css`
- Modify: `app/assets/stylesheets/application.css`
- Test: `spec/requests/stylesheets_spec.rb`

**Interfaces:**
- Produces (CSS custom properties every later task uses): `--bg --surface --hover --fg --muted --border --border-strong --accent --accent-hover --accent-soft --accent-fg --on-accent --ring --neg --neg-soft --pos --pos-soft --warn --warn-soft --chart-income --chart-expense --chart-grid --font-sans --font-mono --text-xs --text-sm --text-base --text-lg --text-xl --text-2xl --space-1 … --space-8 --radius-sm --radius --radius-lg --shadow-pop`.
- Produces classes: `.num .neg .pos .muted .errors .primary .danger .ghost .flash .flash-notice .flash-alert .badge .badge-pos .badge-warn .badge-neg .badge-muted .card .card-title .empty`.

- [ ] **Step 1: Write the failing test**

```ruby
# spec/requests/stylesheets_spec.rb
require "rails_helper"

RSpec.describe "Stylesheets" do
  before { create(:household) }

  it "links the design system stylesheets and serves the fonts they reference" do
    get new_session_path
    hrefs = Nokogiri::HTML(response.body).css("link[rel=stylesheet]").map { _1[:href] }
    expect(hrefs).to include(a_string_matching(%r{/assets/tokens-}), a_string_matching(%r{/assets/fonts-}), a_string_matching(%r{/assets/base-}))

    get hrefs.find { _1.include?("/assets/fonts-") }
    font_urls = response.body.scan(/url\("([^"]+\.woff2)"\)/).flatten
    expect(font_urls.size).to eq(5)
    font_urls.each do |url|
      get url
      expect(response).to have_http_status(:ok)
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bundle exec rspec spec/requests/stylesheets_spec.rb`
Expected: FAIL — `tokens-` stylesheet not linked.

- [ ] **Step 3: Download the fonts (pinned versions)**

```bash
mkdir -p app/assets/fonts
base_sans=https://cdn.jsdelivr.net/npm/@ibm/plex-sans@1.1.0
base_mono=https://cdn.jsdelivr.net/npm/@ibm/plex-mono@1.1.0
for w in Regular Medium SemiBold; do curl -fsSL -o app/assets/fonts/IBMPlexSans-$w-Latin1.woff2 $base_sans/fonts/split/woff2/IBMPlexSans-$w-Latin1.woff2; done
for w in Regular Medium; do curl -fsSL -o app/assets/fonts/IBMPlexMono-$w-Latin1.woff2 $base_mono/fonts/split/woff2/IBMPlexMono-$w-Latin1.woff2; done
curl -fsSL -o app/assets/fonts/OFL.txt $base_sans/LICENSE.txt
file app/assets/fonts/*.woff2   # each must say "Web Open Font Format (Version 2)"
```

- [ ] **Step 4: Create `app/assets/stylesheets/fonts.css`**

```css
@font-face { font-family: "IBM Plex Sans"; font-weight: 400; font-style: normal; font-display: swap; src: url("/IBMPlexSans-Regular-Latin1.woff2") format("woff2"); }
@font-face { font-family: "IBM Plex Sans"; font-weight: 500; font-style: normal; font-display: swap; src: url("/IBMPlexSans-Medium-Latin1.woff2") format("woff2"); }
@font-face { font-family: "IBM Plex Sans"; font-weight: 600; font-style: normal; font-display: swap; src: url("/IBMPlexSans-SemiBold-Latin1.woff2") format("woff2"); }
@font-face { font-family: "IBM Plex Mono"; font-weight: 400; font-style: normal; font-display: swap; src: url("/IBMPlexMono-Regular-Latin1.woff2") format("woff2"); }
@font-face { font-family: "IBM Plex Mono"; font-weight: 500; font-style: normal; font-display: swap; src: url("/IBMPlexMono-Medium-Latin1.woff2") format("woff2"); }
```

(Propshaft rewrites `url("/name.woff2")` to the digested `/assets/name-<digest>.woff2`.)

- [ ] **Step 5: Create `app/assets/stylesheets/tokens.css`**

```css
:root {
  color-scheme: light dark;

  --bg: light-dark(#f6f7fb, #07080f);
  --surface: light-dark(#ffffff, #0e1020);
  --hover: light-dark(#f3f4f9, #141730);
  --fg: light-dark(#0f1222, #e7e9f5);
  --muted: light-dark(#646a85, #9a9fbd);
  --border: light-dark(#e2e5ef, #1f2340);
  --border-strong: light-dark(#cfd3e3, #2c3156);
  --accent: light-dark(#4f46e5, #818cf8);
  --accent-hover: light-dark(#4338ca, #a5b4fc);
  --accent-soft: light-dark(#eef2ff, #1e1b4b);
  --accent-fg: light-dark(#3730a3, #c7d2fe);
  --on-accent: light-dark(#ffffff, #0e1020);
  --ring: light-dark(rgb(79 70 229 / .25), rgb(129 140 248 / .35));
  --neg: light-dark(#e11d48, #fb7185);
  --neg-soft: light-dark(#fff1f2, #2a0f1a);
  --pos: light-dark(#0f9f6e, #34d399);
  --pos-soft: light-dark(#ecfdf5, #062a1e);
  --warn: light-dark(#b45309, #fbbf24);
  --warn-soft: light-dark(#fffbeb, #2a1f05);
  --chart-income: var(--accent);
  --chart-expense: light-dark(#c7cbe0, #2e3358);
  --chart-grid: light-dark(#eceef5, #181b33);

  --font-sans: "IBM Plex Sans", system-ui, sans-serif;
  --font-mono: "IBM Plex Mono", ui-monospace, monospace;
  --text-xs: 11px;
  --text-sm: 12.5px;
  --text-base: 13.5px;
  --text-lg: 16px;
  --text-xl: 19px;
  --text-2xl: 22px;

  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 20px;
  --space-6: 24px;
  --space-7: 28px;
  --space-8: 32px;

  --radius-sm: 6px;
  --radius: 8px;
  --radius-lg: 10px;
  --shadow-pop: 0 8px 24px rgb(15 18 34 / .14);
}

:root[data-theme="light"] { color-scheme: light; }
:root[data-theme="dark"] { color-scheme: dark; }

@media print {
  :root, :root[data-theme] { color-scheme: light; }
}
```

- [ ] **Step 6: Create `app/assets/stylesheets/base.css`**

```css
*, *::before, *::after { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font: 400 var(--text-base)/1.5 var(--font-sans);
  -webkit-font-smoothing: antialiased;
}

h1, h2, h3 { margin: 0 0 var(--space-3); font-weight: 600; letter-spacing: -0.015em; line-height: 1.25; }
h1 { font-size: var(--text-2xl); }
h2 { font-size: var(--text-xl); }
h3 { font-size: var(--text-lg); }
p { margin: 0 0 var(--space-3); }

a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }

table {
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  overflow: hidden;
  margin-bottom: var(--space-4);
}
th, td { text-align: left; padding: 7px var(--space-3); border-bottom: 1px solid var(--border); }
th { font-size: var(--text-xs); font-weight: 500; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; }
tbody tr:hover td { background: var(--hover); }
tr:last-child td { border-bottom: 0; }
tfoot td, tfoot th { font-weight: 600; border-top: 1px solid var(--border-strong); color: var(--fg); }

.num { text-align: right; font-family: var(--font-mono); font-size: .95em; font-variant-numeric: tabular-nums; }
.neg { color: var(--neg); }
.pos { color: var(--pos); }
.muted { color: var(--muted); }

label { display: block; font-weight: 500; font-size: var(--text-sm); margin-bottom: var(--space-1); }
input:not([type=checkbox], [type=radio], [type=submit], [type=button], [type=hidden]), select, textarea {
  font: inherit;
  width: 100%;
  max-width: 28rem;
  padding: 6px 9px;
  border: 1px solid var(--border-strong);
  border-radius: var(--radius-sm);
  background: var(--surface);
  color: var(--fg);
}
input:focus-visible, select:focus-visible, textarea:focus-visible, button:focus-visible, a:focus-visible {
  outline: 0;
  border-color: var(--accent);
  box-shadow: 0 0 0 3px var(--ring);
}
.field_with_errors input, .field_with_errors select, .field_with_errors textarea { border-color: var(--neg); }
.field_with_errors label { color: var(--neg); }
form > div, form > p { margin-bottom: var(--space-3); }

.errors {
  background: var(--neg-soft);
  color: var(--neg);
  border: 1px solid color-mix(in srgb, var(--neg) 30%, transparent);
  border-radius: var(--radius);
  padding: var(--space-2) var(--space-3);
  margin-bottom: var(--space-4);
}
.errors ul { margin: 0; padding-left: var(--space-5); }
```

- [ ] **Step 7: Create the core component files**

`app/assets/stylesheets/components/buttons.css`:

```css
button, input[type=submit], input[type=button] {
  font: inherit;
  font-size: var(--text-sm);
  font-weight: 500;
  padding: 6px 12px;
  border-radius: var(--radius-sm);
  border: 1px solid var(--border-strong);
  background: var(--surface);
  color: var(--fg);
  cursor: pointer;
}
button:hover, input[type=submit]:hover, input[type=button]:hover { background: var(--hover); }
form.button_to { display: inline; }

.primary { background: var(--accent); border-color: var(--accent); color: var(--on-accent); }
.primary:hover { background: var(--accent-hover); border-color: var(--accent-hover); }
.danger { color: var(--neg); }
.ghost { background: transparent; border-color: transparent; color: var(--muted); }
.ghost:hover { color: var(--fg); }
```

`app/assets/stylesheets/components/flash.css`:

```css
.flash {
  padding: var(--space-2) var(--space-3);
  border-radius: var(--radius);
  border: 1px solid;
  margin: 0 0 var(--space-4);
  font-size: var(--text-sm);
}
.flash-notice { background: var(--pos-soft); color: var(--pos); border-color: color-mix(in srgb, var(--pos) 30%, transparent); }
.flash-alert { background: var(--neg-soft); color: var(--neg); border-color: color-mix(in srgb, var(--neg) 30%, transparent); }
```

`app/assets/stylesheets/components/badge.css`:

```css
.badge {
  display: inline-block;
  font-size: var(--text-xs);
  font-weight: 500;
  line-height: 1.6;
  padding: 0 8px;
  border-radius: 999px;
  background: var(--accent-soft);
  color: var(--accent-fg);
}
.badge-pos { background: var(--pos-soft); color: var(--pos); }
.badge-warn { background: var(--warn-soft); color: var(--warn); }
.badge-neg { background: var(--neg-soft); color: var(--neg); }
.badge-muted { background: var(--hover); color: var(--muted); }
```

`app/assets/stylesheets/components/card.css`:

```css
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  padding: var(--space-3) var(--space-4);
  margin-bottom: var(--space-3);
}
.card > table { border: 0; border-radius: 0; margin: 0; }
.card-title {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  gap: var(--space-3);
  font-size: var(--text-sm);
  font-weight: 600;
  letter-spacing: 0;
  margin: 0 0 var(--space-2);
}
.card-title small { font-weight: 400; color: var(--muted); font-size: var(--text-xs); }
```

`app/assets/stylesheets/components/empty.css`:

```css
.empty {
  border: 1px dashed var(--border-strong);
  border-radius: var(--radius);
  padding: var(--space-5);
  text-align: center;
  color: var(--muted);
}
.empty strong { display: block; color: var(--fg); margin-bottom: 2px; }
```

- [ ] **Step 8: Trim `app/assets/stylesheets/application.css`** to rules not covered elsewhere (the old `:root`, `body`, table, `.num`, flash and `.errors` rules are superseded; header/nav rules are replaced in Task 4 but stay for now so the current layout keeps working):

```css
main { max-width: 1100px; margin: 0 auto; padding: 1rem; }
.site-header { display: flex; justify-content: space-between; align-items: center; padding: .75rem 1rem; border-bottom: 1px solid var(--border); }
.site-nav { display: flex; gap: 1rem; align-items: center; }
.site-nav form { display: inline; }
.business-nav ul { display: flex; flex-wrap: wrap; gap: 1rem; list-style: none; padding: 0; }
.inline-form { display: inline-flex; gap: .25rem; align-items: center; }
@media print { .no-print, .business-nav, .site-header { display: none; } }
.drag-handle { cursor: grab; user-select: none; padding: 0 .5rem; font-size: 1.2rem; }
.sortable-ghost { opacity: .4; }
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `bundle exec rspec spec/requests/stylesheets_spec.rb` → PASS.

- [ ] **Step 10: Run the full suite** → `0 failures`.

- [ ] **Step 11: Commit**

```bash
git add app/assets spec/requests/stylesheets_spec.rb
git commit -m "Add design tokens, IBM Plex, and base element styles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Theme cookie, `data-theme`, and `PATCH /theme`

**Files:**
- Create: `app/models/theme.rb`, `app/helpers/theme_helper.rb`, `app/controllers/themes_controller.rb`
- Modify: `config/routes.rb`, `app/views/layouts/application.html.erb:2`
- Test: `spec/requests/theme_spec.rb`

**Interfaces:**
- Produces: `Theme::CHOICES = %w[system light dark]`, `Theme::COOKIE = :theme`, `Theme.normalize(value) -> "system" | "light" | "dark"`.
- Produces helpers: `current_theme -> String` (normalized cookie), `theme_attribute -> "light" | "dark" | nil`.
- Produces route: `theme_path` (`PATCH /theme`, param `theme`).

- [ ] **Step 1: Write the first failing test**

```ruby
# spec/requests/theme_spec.rb
require "rails_helper"

RSpec.describe "Theme" do
  before { create(:household) }

  def html_theme = Nokogiri::HTML(response.body).at("html")["data-theme"]

  it "renders the cookie's theme on <html>" do
    cookies[:theme] = "dark"
    get new_session_path
    expect(html_theme).to eq("dark")
  end
end
```

- [ ] **Step 2: Run it** — `bundle exec rspec spec/requests/theme_spec.rb` → FAIL (`nil` instead of `"dark"`).

- [ ] **Step 3: Implement the model, helper, and layout attribute**

```ruby
# app/models/theme.rb
module Theme
  CHOICES = %w[system light dark].freeze
  COOKIE = :theme

  def self.normalize(value) = CHOICES.include?(value) ? value : "system"
end
```

```ruby
# app/helpers/theme_helper.rb
module ThemeHelper
  def current_theme = Theme.normalize(cookies[Theme::COOKIE])

  def theme_attribute = (current_theme unless current_theme == "system")
end
```

In `app/views/layouts/application.html.erb` change line 2 from `<html>` to:

```erb
<html <%= tag.attributes(data: { theme: theme_attribute }) %>>
```

(`tag.attributes` omits nil values, so System renders `<html >`.)

- [ ] **Step 4: Run it** → PASS.

- [ ] **Step 5: Add the next tests one at a time, running each**

```ruby
  it "renders light" do
    cookies[:theme] = "light"
    get new_session_path
    expect(html_theme).to eq("light")
  end

  it "omits the attribute for system, missing, or tampered values" do
    [ "system", "blue", "\"><script>alert(1)</script>" ].each do |value|
      cookies[:theme] = value
      get new_session_path
      expect(html_theme).to be_nil
      expect(response.body).not_to include("<script>alert(1)")
    end
  end
```

- [ ] **Step 6: Write the failing endpoint test**

```ruby
  describe "PATCH /theme" do
    it "stores a valid choice and redirects back" do
      patch theme_path, params: { theme: "dark" }, headers: { "HTTP_REFERER" => "http://www.example.com/session/new" }
      expect(response).to redirect_to("http://www.example.com/session/new")
      expect(cookies[:theme]).to eq("dark")
    end
  end
```

Run → FAIL (`undefined local variable or method 'theme_path'`).

- [ ] **Step 7: Add the route and controller**

In `config/routes.rb`, next to the other singular resources (e.g. after `resource :session`):

```ruby
  resource :theme, only: :update
```

```ruby
# app/controllers/themes_controller.rb
class ThemesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_household

  def update
    if Theme::CHOICES.include?(params[:theme])
      cookies[Theme::COOKIE] = { value: params[:theme], expires: 1.year, same_site: :lax }
    end
    redirect_back_or_to root_path
  end
end
```

Run → PASS.

- [ ] **Step 8: Add the remaining endpoint tests one at a time**

```ruby
    it "ignores unknown values" do
      patch theme_path, params: { theme: "neon" }
      expect(response).to redirect_to(root_path)
      expect(cookies[:theme]).to be_blank
    end

    it "works for signed-in users" do
      business = create(:business)
      sign_in_as user_with_role("viewer", business)
      patch theme_path, params: { theme: "light" }
      expect(cookies[:theme]).to eq("light")
    end
```

- [ ] **Step 9: Full suite + rubocop** — `bundle exec rspec && bundle exec rubocop` → clean.

- [ ] **Step 10: Commit**

```bash
git add app/models/theme.rb app/helpers/theme_helper.rb app/controllers/themes_controller.rb config/routes.rb app/views/layouts/application.html.erb spec/requests/theme_spec.rb
git commit -m "Add theme cookie and PATCH /theme; render data-theme on <html>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Sidebar shell, signed-out layout, remove `business_nav`

**Files:**
- Create: `app/views/layouts/_sidebar.html.erb`, `app/views/layouts/_business_switcher.html.erb`, `app/views/layouts/_flash.html.erb`, `app/helpers/navigation_helper.rb`, `app/assets/stylesheets/layout.css`
- Modify: `app/views/layouts/application.html.erb`, `app/helpers/application_helper.rb`, `app/assets/stylesheets/application.css`, the 24 views containing `<%= business_nav @business %>`
- Delete: `app/views/businesses/_nav.html.erb`
- Test: `spec/requests/navigation_spec.rb`

**Interfaces:**
- Consumes: `current_membership` (helper method from `BusinessScoped`, only present when `@business` is set), `Current.user` methods `household_owner?`, `can_view_household?`, `accessible_businesses`, `memberships.owner`.
- Produces: `nav_link(name, path, badge: nil)` → `<a href aria-current="page"?>name <span class="badge">n</span>?</a>`; `business_inbox_count(business) -> Integer`.
- Produces markup later tasks hook into: `<div class="app-shell">` wrapping `<nav class="sidebar" id="sidebar">` and `<main class="app-main">`; `<div class="sidebar-footer">` (Task 5 inserts the theme toggle there); signed-out `<main class="auth-main">` containing `<div class="auth-card">` (Task 5 puts the toggle after it).

- [ ] **Step 1: Write the first failing test**

```ruby
# spec/requests/navigation_spec.rb
require "rails_helper"

RSpec.describe "Navigation" do
  let!(:household) { create(:household) }
  let!(:person) { create(:person, household: household) }
  let(:household_owner) { create(:user, :household_owner) }
  let!(:business) { BusinessProvisioner.call(build(:business, person: person, name: "Studio LLC"), owner: household_owner) }

  def sidebar = Capybara.string(response.body).find("nav.sidebar")

  it "shows the business section with every business page on a business page" do
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(sidebar).to have_link("Overview", href: business_path(business))
    expect(sidebar).to have_link("Inbox", href: business_inbox_path(business))
    expect(sidebar).to have_link("Transactions", href: business_transactions_path(business))
    expect(sidebar).to have_link("Accounts", href: business_accounts_path(business))
    expect(sidebar).to have_link("Categories", href: business_categories_path(business))
    expect(sidebar).to have_link("Rules", href: business_rules_path(business))
    expect(sidebar).to have_link("Mileage", href: business_mileage_entries_path(business))
    expect(sidebar).to have_link("Members", href: business_memberships_path(business))
    expect(sidebar).to have_link("Profit & loss", href: business_profit_and_loss_path(business))
    expect(sidebar).to have_link("Schedule C", href: business_schedule_c_path(business))
  end
end
```

- [ ] **Step 2: Run it** → FAIL (no `nav.sidebar`).

- [ ] **Step 3: Create `app/helpers/navigation_helper.rb`**

```ruby
module NavigationHelper
  def nav_link(name, path, badge: nil)
    link_to path, aria: { current: ("page" if current_page?(path)) } do
      safe_join([ name, (tag.span(badge, class: "badge") if badge&.positive?) ].compact, " ")
    end
  end

  def business_inbox_count(business) = Transaction.for_businesses(business.id).inbox.count
end
```

- [ ] **Step 4: Create the partials**

`app/views/layouts/_flash.html.erb`:

```erb
<% flash.each do |type, message| %>
  <p class="flash flash-<%= type %>"><%= message %></p>
<% end %>
```

`app/views/layouts/_business_switcher.html.erb`:

```erb
<details class="switcher">
  <summary><span class="switcher-dot"></span><%= @business&.name || "goodbooks" %></summary>
  <ul>
    <% Current.user.accessible_businesses.order(:name).each do |business| %>
      <li><%= link_to business.name, business_path(business) %></li>
    <% end %>
  </ul>
</details>
```

`app/views/layouts/_sidebar.html.erb`:

```erb
<nav class="sidebar no-print" id="sidebar" aria-label="Main">
  <%= render "layouts/business_switcher" %>

  <% if @business %>
    <p class="nav-group"><%= @business.name %></p>
    <%= nav_link "Overview", business_path(@business) %>
    <%= nav_link "Inbox", business_inbox_path(@business), badge: business_inbox_count(@business) %>
    <%= nav_link "Transactions", business_transactions_path(@business) %>
    <%= nav_link "Accounts", business_accounts_path(@business) %>
    <%= nav_link "Categories", business_categories_path(@business) %>
    <%= nav_link "Rules", business_rules_path(@business) %>
    <%= nav_link "Mileage", business_mileage_entries_path(@business) %>
    <%= nav_link "Members", business_memberships_path(@business) if current_membership&.owner? %>

    <p class="nav-group">Reports</p>
    <%= nav_link "Profit & loss", business_profit_and_loss_path(@business) %>
    <%= nav_link "Schedule C", business_schedule_c_path(@business) %>
  <% end %>

  <p class="nav-group">Household</p>
  <%= nav_link "All businesses", root_path %>
  <%= nav_link "Household inbox", household_inbox_path %>
  <%= nav_link "Household P&L", household_profit_and_loss_path if Current.user.can_view_household? %>
  <%= nav_link "Tax parameters", tax_parameters_path if Current.user.household_owner? %>
  <%= nav_link "Invites", invites_path if Current.user.household_owner? || Current.user.memberships.owner.exists? %>
  <%= nav_link "People", people_path if Current.user.household_owner? %>

  <div class="sidebar-footer">
    <span class="sidebar-user"><%= Current.user.name.presence || Current.user.email_address %></span>
    <%= button_to "Sign out", session_path, method: :delete, class: "ghost" %>
  </div>
</nav>
```

- [ ] **Step 5: Replace the `<body>` of `app/views/layouts/application.html.erb`** (keep the `<head>` exactly as is, and the `<html …>` line from Task 3):

```erb
  <body>
    <% if authenticated? %>
      <div class="app-shell">
        <%= render "layouts/sidebar" %>
        <main class="app-main">
          <%= render "layouts/flash" %>
          <%= yield %>
        </main>
      </div>
    <% else %>
      <main class="auth-main">
        <p class="auth-brand"><span class="switcher-dot"></span>goodbooks</p>
        <div class="auth-card">
          <%= render "layouts/flash" %>
          <%= yield %>
        </div>
      </main>
    <% end %>
  </body>
```

- [ ] **Step 6: Create `app/assets/stylesheets/layout.css`**

```css
.app-shell { display: grid; grid-template-columns: 224px minmax(0, 1fr); min-height: 100vh; }
.app-main { padding: var(--space-6) var(--space-7); max-width: 1200px; width: 100%; }

.sidebar {
  position: sticky;
  top: 0;
  height: 100vh;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 1px;
  padding: var(--space-3) var(--space-2);
  background: var(--surface);
  border-right: 1px solid var(--border);
  font-size: var(--text-sm);
}
.sidebar > a {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 5px var(--space-2);
  border-radius: var(--radius-sm);
  color: var(--muted);
  text-decoration: none;
}
.sidebar > a:hover { background: var(--hover); color: var(--fg); }
.sidebar > a[aria-current="page"] { background: var(--accent-soft); color: var(--accent-fg); font-weight: 500; }
.sidebar .badge { background: var(--accent); color: var(--on-accent); }
.nav-group {
  margin: var(--space-3) 0 var(--space-1);
  padding: 0 var(--space-2);
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: var(--muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.switcher { position: relative; margin-bottom: var(--space-1); }
.switcher summary {
  display: flex;
  align-items: center;
  gap: var(--space-2);
  padding: 6px var(--space-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  font-weight: 600;
  cursor: pointer;
  list-style: none;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
.switcher summary::-webkit-details-marker { display: none; }
.switcher summary::after { content: "⌄"; margin-left: auto; color: var(--muted); }
.switcher ul {
  position: absolute;
  inset: calc(100% + 4px) 0 auto 0;
  z-index: 10;
  margin: 0;
  padding: var(--space-1);
  list-style: none;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  box-shadow: var(--shadow-pop);
}
.switcher li a { display: block; padding: 5px var(--space-2); border-radius: var(--radius-sm); color: var(--fg); }
.switcher li a:hover { background: var(--hover); text-decoration: none; }
.switcher-dot { flex: none; display: inline-block; width: 10px; height: 10px; border-radius: 3px; background: var(--accent); }

.sidebar-footer {
  margin-top: auto;
  padding: var(--space-3) var(--space-2) 0;
  border-top: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  color: var(--muted);
}
.sidebar-footer > form.button_to button { padding-left: 0; }

.auth-main { min-height: 100vh; display: grid; place-content: center; justify-items: center; gap: var(--space-4); padding: var(--space-6); }
.auth-brand { display: flex; align-items: center; gap: var(--space-2); font-weight: 600; font-size: var(--text-lg); letter-spacing: -0.02em; margin: 0; }
.auth-card {
  width: min(400px, 100vw - 2 * var(--space-6));
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg);
  padding: var(--space-6);
}
.auth-card input:not([type=submit]) { max-width: none; }

@media print {
  .app-shell { display: block; }
  .no-print { display: none !important; }
  .app-main { padding: 0; max-width: none; }
}
```

- [ ] **Step 7: Run the test** → PASS.

- [ ] **Step 8: Add role and context tests one at a time, running each**

```ruby
  it "hides owner-only links from viewers" do
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business)
    expect(sidebar).to have_no_link("Members")
    expect(sidebar).to have_no_link("Tax parameters")
    expect(sidebar).to have_no_link("People")
    expect(sidebar).to have_no_link("Invites")
  end

  it "shows household owner links" do
    sign_in_as household_owner
    get root_path
    expect(sidebar).to have_link("All businesses", href: root_path)
    expect(sidebar).to have_link("Household inbox", href: household_inbox_path)
    expect(sidebar).to have_link("Household P&L", href: household_profit_and_loss_path)
    expect(sidebar).to have_link("Tax parameters", href: tax_parameters_path)
    expect(sidebar).to have_link("Invites", href: invites_path)
    expect(sidebar).to have_link("People", href: people_path)
  end

  it "omits the business section outside a business" do
    sign_in_as household_owner
    get root_path
    expect(sidebar).to have_no_link("Overview")
    expect(sidebar).to have_no_css(".nav-group", text: "Reports")
  end

  it "renders for a user with no memberships" do
    sign_in_as create(:user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(sidebar).to have_no_link("Overview")
    expect(sidebar).to have_no_link("Household P&L")
    expect(sidebar).to have_no_css(".switcher li")
  end

  it "lists accessible businesses in the switcher" do
    other = create(:business, name: "Hidden Co")
    sign_in_as user_with_role("viewer", business)
    get business_transactions_path(business)
    expect(sidebar).to have_css(".switcher li a", text: "Studio LLC")
    expect(sidebar).to have_no_text(other.name)
  end

  it "badges the inbox with the uncategorized count" do
    account = create(:account, business: business)
    create_list(:transaction, 2, account: account, category: nil)
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(sidebar.find_link("Inbox", href: business_inbox_path(business))).to have_css(".badge", text: "2")
  end

  it "marks the current page" do
    sign_in_as household_owner
    get business_rules_path(business)
    expect(sidebar).to have_css('a[aria-current="page"]', text: "Rules")
  end

  it "renders signed-out pages in the auth card without a sidebar" do
    get new_session_path
    page = Capybara.string(response.body)
    expect(page).to have_no_css("nav.sidebar")
    expect(page).to have_css(".auth-card form")
  end
```

If `GET root_path` for a user with no memberships does not return 200 today (check `DashboardsController`), assert whatever it returns today and keep only the sidebar expectations for a page that renders.

- [ ] **Step 9: Write the failing "old nav is gone" test**

```ruby
  it "no longer renders the in-page business nav" do
    sign_in_as household_owner
    get business_transactions_path(business)
    expect(response.body).not_to include("business-nav")
  end
```

Run → FAIL (old partial still rendered).

- [ ] **Step 10: Remove `business_nav` entirely**

```bash
grep -rl '<%= business_nav @business %>' app/views | xargs sed -i '' '/^<%= business_nav @business %>$/d'
grep -rn "business_nav" app spec   # must print only the helper definition
git rm app/views/businesses/_nav.html.erb
```

Delete the `business_nav` method from `app/helpers/application_helper.rb`. Then reduce `app/assets/stylesheets/application.css` to:

```css
.inline-form { display: inline-flex; gap: .25rem; align-items: center; }
.drag-handle { cursor: grab; user-select: none; padding: 0 .5rem; font-size: 1.2rem; }
.sortable-ghost { opacity: .4; }
```

Confirm `grep -rn "business_nav\|business-nav\|site-header\|site-nav" app spec` prints nothing.

- [ ] **Step 11: Run the navigation spec, then the full suite** — `bundle exec rspec` → `0 failures`. (`system_sign_in_as` waits for "Sign out", which is now in the sidebar footer.)

- [ ] **Step 12: rubocop + commit**

```bash
bundle exec rubocop
git add -A app spec
git commit -m "Replace top nav with sidebar shell; remove business_nav

Signed-out pages render in a centered card. The in-page business nav,
its helper, partial, CSS and all call sites are gone.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Theme toggle UI

**Files:**
- Create: `app/views/layouts/_theme_toggle.html.erb`, `app/javascript/controllers/theme_controller.js`, `app/assets/stylesheets/components/segmented.css`
- Modify: `app/views/layouts/_sidebar.html.erb` (footer), `app/views/layouts/application.html.erb` (auth branch)
- Test: `spec/requests/theme_spec.rb` (add), `spec/system/theme_toggle_spec.rb`

**Interfaces:**
- Consumes: `Theme::CHOICES`, `current_theme`, `theme_path` (Task 3); `.sidebar-footer`, `.auth-main` (Task 4).
- Produces: `.segmented` component (Task 10 reuses it for the period control): a container whose direct children are links or `button_to` forms; the current one has `aria-current="page"` (links) or `aria-pressed="true"` (buttons).

- [ ] **Step 1: Write the failing request test** (append inside the top-level describe in `spec/requests/theme_spec.rb`)

```ruby
  it "renders the toggle with the current choice pressed" do
    cookies[:theme] = "dark"
    get new_session_path
    toggle = Capybara.string(response.body).find(".theme-toggle")
    expect(toggle).to have_css('button[aria-pressed="true"]', text: "Dark")
    expect(toggle).to have_css('button[aria-pressed="false"]', text: "System")
    expect(toggle).to have_css('button[aria-pressed="false"]', text: "Light")
  end
```

Run → FAIL (no `.theme-toggle`).

- [ ] **Step 2: Create the partial and render it**

`app/views/layouts/_theme_toggle.html.erb`:

```erb
<div class="segmented theme-toggle" role="group" aria-label="Theme" data-controller="theme">
  <% Theme::CHOICES.each do |choice| %>
    <%= button_to choice.capitalize, theme_path, method: :patch, params: { theme: choice },
          form: { data: { action: "submit->theme#choose" } },
          aria: { pressed: current_theme == choice },
          data: { theme_target: "option", theme_choice: choice } %>
  <% end %>
</div>
```

In `app/views/layouts/_sidebar.html.erb`, inside `.sidebar-footer`, between the user name and Sign out:

```erb
    <%= render "layouts/theme_toggle" %>
```

In `app/views/layouts/application.html.erb`, in the signed-out branch, after the closing `</div>` of `.auth-card`:

```erb
        <%= render "layouts/theme_toggle" %>
```

Run → PASS. Then add and run:

```ruby
  it "shows the toggle to signed-in users" do
    business = create(:business)
    sign_in_as user_with_role("viewer", business)
    get root_path
    expect(Capybara.string(response.body).find("nav.sidebar")).to have_css(".theme-toggle")
  end
```

- [ ] **Step 3: Create `app/assets/stylesheets/components/segmented.css`**

```css
.segmented {
  display: inline-flex;
  border: 1px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--surface);
  overflow: hidden;
  font-size: var(--text-sm);
}
.segmented > a, .segmented button {
  display: block;
  padding: 3px 10px;
  border: 0;
  border-radius: 0;
  background: transparent;
  color: var(--muted);
  font-weight: 400;
  text-decoration: none;
}
.segmented > * + * { border-left: 1px solid var(--border); }
.segmented > a:hover, .segmented button:hover { color: var(--fg); background: var(--hover); }
.segmented > a[aria-current="page"], .segmented button[aria-pressed="true"] { background: var(--accent-soft); color: var(--accent-fg); font-weight: 500; }
.segmented form.button_to { display: block; }
```

- [ ] **Step 4: Write the failing system test**

```ruby
# spec/system/theme_toggle_spec.rb
require "rails_helper"

RSpec.describe "Theme toggle", js: true do
  let!(:business) { create(:business) }

  it "switches theme without reloading and remembers it" do
    system_sign_in_as user_with_role("viewer", business)
    page.execute_script("window.__noReload = true")

    within(".theme-toggle") { click_button "Dark" }

    expect(page).to have_css("html[data-theme='dark']")
    expect(page.evaluate_script("window.__noReload")).to be(true)
    expect(page).to have_css(".theme-toggle button[aria-pressed='true']", text: "Dark")

    visit root_path
    expect(page).to have_css("html[data-theme='dark']")

    within(".theme-toggle") { click_button "System" }
    expect(page).to have_no_css("html[data-theme]")
  end
end
```

Run: `bundle exec rspec spec/system/theme_toggle_spec.rb` → FAIL (the form submits normally and reloads, so `__noReload` is nil).

- [ ] **Step 5: Create `app/javascript/controllers/theme_controller.js`**

```js
import { Controller } from "@hotwired/stimulus"

// Applies a theme instantly and stores it in the same cookie the server reads.
export default class extends Controller {
  static targets = ["option"]

  choose(event) {
    event.preventDefault()
    const theme = event.target.querySelector("input[name=theme]").value
    document.cookie = `theme=${theme}; path=/; max-age=31536000; samesite=lax`

    if (theme === "system") {
      delete document.documentElement.dataset.theme
    } else {
      document.documentElement.dataset.theme = theme
    }

    this.optionTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.themeChoice === theme))
    })
  }
}
```

(`eagerLoadControllersFrom` in `controllers/index.js` registers it automatically; no importmap change needed.)

- [ ] **Step 6: Run the system test** → PASS. Then the full suite → `0 failures`.

- [ ] **Step 7: Commit**

```bash
git add app/views/layouts app/javascript/controllers/theme_controller.js app/assets/stylesheets/components/segmented.css spec
git commit -m "Add System/Light/Dark theme toggle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Mobile sidebar drawer

**Files:**
- Create: `app/javascript/controllers/sidebar_controller.js`, `spec/system/sidebar_drawer_spec.rb`
- Modify: `app/views/layouts/application.html.erb` (shell), `app/assets/stylesheets/layout.css`

**Interfaces:**
- Consumes: `.app-shell`, `nav.sidebar#sidebar` (Task 4).
- Produces: `.topbar` (hidden above 800px) with a `Menu` button; `.app-shell.sidebar-open` state.

- [ ] **Step 1: Write the failing system test**

```ruby
# spec/system/sidebar_drawer_spec.rb
require "rails_helper"

RSpec.describe "Sidebar drawer", js: true do
  let!(:business) { create(:business) }

  after { page.current_window.resize_to(1400, 900) }

  it "hides the sidebar behind a menu button on narrow screens" do
    system_sign_in_as user_with_role("viewer", business)
    page.current_window.resize_to(600, 900)
    visit root_path

    expect(page).to have_no_css("nav.sidebar", visible: :visible)
    click_button "Menu"
    expect(page).to have_css("nav.sidebar", visible: :visible)
    expect(page).to have_button("Menu", exact: true) { _1["aria-expanded"] == "true" }
    click_button "Menu"
    expect(page).to have_no_css("nav.sidebar", visible: :visible)
  end
end
```

Run → FAIL (no Menu button).

- [ ] **Step 2: Add the top bar and controller hooks** — in `app/views/layouts/application.html.erb` change the signed-in branch to:

```erb
      <div class="app-shell" data-controller="sidebar">
        <header class="topbar no-print">
          <button type="button" class="ghost" aria-controls="sidebar" aria-expanded="false"
                  data-sidebar-target="button" data-action="sidebar#toggle">Menu</button>
          <%= link_to root_path, class: "auth-brand" do %><span class="switcher-dot"></span>goodbooks<% end %>
        </header>
        <%= render "layouts/sidebar" %>
        <main class="app-main">
          <%= render "layouts/flash" %>
          <%= yield %>
        </main>
      </div>
```

- [ ] **Step 3: Create `app/javascript/controllers/sidebar_controller.js`**

```js
import { Controller } from "@hotwired/stimulus"

// Opens and closes the off-canvas sidebar on narrow screens.
export default class extends Controller {
  static targets = ["button"]

  toggle() {
    const open = this.element.classList.toggle("sidebar-open")
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
```

- [ ] **Step 4: Append the drawer styles to `app/assets/stylesheets/layout.css`** (before the `@media print` block). The top bar stays above the drawer so the Menu button remains clickable while it is open.

```css
.topbar { display: none; }

@media (max-width: 800px) {
  .app-shell { grid-template-columns: minmax(0, 1fr); }
  .topbar {
    display: flex;
    align-items: center;
    gap: var(--space-3);
    height: 45px;
    padding: 0 var(--space-3);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    position: sticky;
    top: 0;
    z-index: 40;
  }
  .sidebar {
    position: fixed;
    inset: 45px auto 0 0;
    height: auto;
    width: 260px;
    z-index: 30;
    box-shadow: var(--shadow-pop);
    transform: translateX(-100%);
    visibility: hidden;
    transition: transform .18s ease, visibility .18s;
  }
  .sidebar-open .sidebar { transform: none; visibility: visible; }
  .app-main { padding: var(--space-4); }
}
```

- [ ] **Step 5: Run the system test** → PASS. Full suite → `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add app/views/layouts/application.html.erb app/javascript/controllers/sidebar_controller.js app/assets/stylesheets/layout.css spec/system/sidebar_drawer_spec.rb
git commit -m "Collapse the sidebar into a drawer on narrow screens

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `Reports::MonthlyTotals`

**Files:**
- Create: `app/models/reports/monthly_totals.rb`, `spec/models/reports/monthly_totals_spec.rb`

**Interfaces:**
- Produces: `Reports::MonthlyTotals.load(business_ids:, year:, through_month:) -> Array<Reports::MonthlyTotals::Month>`; `Month = Data.define(:month, :income_cents, :expense_cents)`; `month` is 1–12; both cents are non-negative magnitudes; one row per month 1..through_month, zero-filled.

- [ ] **Step 1: Write the first failing test**

```ruby
# spec/models/reports/monthly_totals_spec.rb
require "rails_helper"

RSpec.describe Reports::MonthlyTotals do
  let(:business) { create(:business) }
  let(:account) { create(:account, business: business) }
  let(:income) { create(:category, :income, business: business) }
  let(:expense) { create(:category, business: business) }

  def totals(through_month: 3, year: 2026, business_ids: [ business.id ])
    described_class.load(business_ids:, year:, through_month:)
  end

  it "returns one zero-filled row per month through the given month" do
    expect(totals.map(&:month)).to eq([ 1, 2, 3 ])
    expect(totals.map(&:income_cents)).to eq([ 0, 0, 0 ])
    expect(totals.map(&:expense_cents)).to eq([ 0, 0, 0 ])
  end
end
```

Run → FAIL (`uninitialized constant Reports::MonthlyTotals`).

- [ ] **Step 2: Minimal implementation**

```ruby
# app/models/reports/monthly_totals.rb
module Reports
  module MonthlyTotals
    Month = Data.define(:month, :income_cents, :expense_cents)
    MONTH_SQL = Arel.sql("CAST(strftime('%m', transactions.posted_on) AS INTEGER)")

    def self.load(business_ids:, year:, through_month:)
      range = Date.new(year, 1, 1)..Date.new(year, through_month, -1)
      sums = Transaction.countable.for_businesses(business_ids).where(posted_on: range).joins(:category)
        .group(MONTH_SQL, "categories.kind").sum("transactions.amount_cents")

      (1..through_month).map do |month|
        Month.new(month:, income_cents: sums.fetch([ month, "income" ], 0), expense_cents: -sums.fetch([ month, "expense" ], 0))
      end
    end
  end
end
```

Run → PASS.

- [ ] **Step 3: Add tests one at a time, running each**

```ruby
  it "sums income and expense per month as positive magnitudes" do
    create(:transaction, account:, category: income, posted_on: Date.new(2026, 2, 3), amount_cents: 400_000)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 9), amount_cents: -5_499)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 2, 28), amount_cents: -1_000)
    expect(totals(through_month: 2).last).to have_attributes(month: 2, income_cents: 400_000, expense_cents: 6_499)
  end

  it "ignores uncategorized, transfer, and excluded transactions" do
    create(:transaction, account:, category: nil, posted_on: Date.new(2026, 1, 5), amount_cents: -100)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 1, 5), amount_cents: -200, excluded: true)
    create(:transaction, account:, transfer: true, posted_on: Date.new(2026, 1, 5), amount_cents: -300)
    expect(totals(through_month: 1).first.expense_cents).to eq(0)
  end

  it "ignores other years, later months, and other businesses" do
    other_account = create(:account, business: create(:business))
    other_expense = create(:category, business: other_account.business)
    create(:transaction, account:, category: expense, posted_on: Date.new(2025, 1, 5), amount_cents: -100)
    create(:transaction, account:, category: expense, posted_on: Date.new(2026, 4, 1), amount_cents: -100)
    create(:transaction, account: other_account, category: other_expense, posted_on: Date.new(2026, 1, 5), amount_cents: -100)
    expect(totals(through_month: 3).sum(&:expense_cents)).to eq(0)
  end

  it "includes the last day of the final month" do
    create(:transaction, account:, category: income, posted_on: Date.new(2026, 2, 28), amount_cents: 100)
    expect(totals(through_month: 2).last.income_cents).to eq(100)
  end
```

- [ ] **Step 4: Full suite + rubocop, then commit**

```bash
git add app/models/reports/monthly_totals.rb spec/models/reports/monthly_totals_spec.rb
git commit -m "Add Reports::MonthlyTotals for the overview chart

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `bar_chart` SVG helper

**Files:**
- Create: `app/helpers/charts_helper.rb`, `app/assets/stylesheets/components/chart.css`, `spec/helpers/charts_helper_spec.rb`

**Interfaces:**
- Produces: `bar_chart(labels:, series:, label:, faded_last: false) -> ActiveSupport::SafeBuffer` (an `<svg class="chart" role="img" aria-label=label viewBox="0 0 600 220">`). `labels`: `Array<String>`; `series`: `Array<{ key: String, name: String, values: Array<Integer cents> }>`. Each positive value renders `<rect class="bar bar-<key>[ faded]">` with a `<title>` of `"<label> <name.downcase>: <Money>"`. Gridlines are `<line class="chart-grid">` at 0, ¼, ½, ¾, max; axis text is `<text class="chart-axis">`.
- Produces: `compact_dollars(cents) -> String` (`0 → "$0"`, `50_000 → "$500"`, `250_000 → "$2.5k"`, `2_000_000 → "$20k"`).

- [ ] **Step 1: Write the first failing test**

```ruby
# spec/helpers/charts_helper_spec.rb
require "rails_helper"

RSpec.describe ChartsHelper do
  def chart(labels: %w[Jan Feb], income: [ 100_000, 200_000 ], expense: [ 50_000, 0 ], **opts)
    html = helper.bar_chart(labels:, label: "Monthly income and expenses",
                            series: [ { key: "income", name: "Income", values: income },
                                      { key: "expense", name: "Expenses", values: expense } ], **opts)
    Capybara.string(html)
  end

  describe "#bar_chart" do
    it "draws one bar per positive value" do
      expect(chart).to have_css("rect.bar", count: 3)
      expect(chart).to have_css("rect.bar-income", count: 2)
      expect(chart).to have_css("rect.bar-expense", count: 1)
    end
  end
end
```

Run → FAIL (`undefined method 'bar_chart'`).

- [ ] **Step 2: Implement**

```ruby
# app/helpers/charts_helper.rb
module ChartsHelper
  WIDTH = 600
  HEIGHT = 220
  LEFT = 48
  RIGHT = 592
  TOP = 12
  BOTTOM = 192
  GRID_STEPS = 4

  def bar_chart(labels:, series:, label:, faded_last: false)
    max = chart_max(series.flat_map { _1[:values] })
    parts = chart_gridlines(max)
    group_width = labels.empty? ? 0 : (RIGHT - LEFT).to_f / labels.size
    bar_width = group_width * 0.7 / [ series.size, 1 ].max

    labels.each_with_index do |name, i|
      group_x = LEFT + group_width * i
      faded = faded_last && i == labels.size - 1
      series.each_with_index do |s, j|
        value = s[:values][i].to_i
        next unless value.positive?

        height = (BOTTOM - TOP) * value.to_f / max
        parts << tag.rect(x: (group_x + group_width * 0.15 + bar_width * j).round(1), y: (BOTTOM - height).round(1),
                          width: bar_width.round(1), height: height.round(1), rx: 1.5,
                          class: [ "bar", "bar-#{s[:key]}", ("faded" if faded) ]) do
          tag.title("#{name} #{s[:name].downcase}: #{Money.new(value)}")
        end
      end
      parts << tag.text(name, x: (group_x + group_width / 2).round(1), y: HEIGHT - 10, class: "chart-axis", "text-anchor": "middle")
    end

    tag.svg(safe_join(parts), class: "chart", role: "img", aria: { label: }, viewBox: "0 0 #{WIDTH} #{HEIGHT}")
  end

  def compact_dollars(cents)
    dollars = cents / 100.0
    dollars >= 1000 ? "$#{trim_number(dollars / 1000)}k" : "$#{trim_number(dollars)}"
  end

  private

  def chart_gridlines(max)
    (0..GRID_STEPS).flat_map do |step|
      y = (BOTTOM - (BOTTOM - TOP) * step.to_f / GRID_STEPS).round(1)
      [ tag.line(x1: LEFT, x2: RIGHT, y1: y, y2: y, class: "chart-grid"),
        tag.text(compact_dollars(max * step / GRID_STEPS), x: LEFT - 6, y: y + 3, class: "chart-axis", "text-anchor": "end") ]
    end
  end

  # Rounds up to 1, 2, 5 or 10 times a power of ten so gridlines land on round numbers.
  def chart_max(values)
    max = values.max.to_i
    return 100_000 unless max.positive?

    magnitude = 10**Math.log10(max).floor
    [ 1, 2, 5, 10 ].map { _1 * magnitude }.find { _1 >= max }
  end

  def trim_number(number)
    rounded = number.round(1)
    rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
  end
end
```

Run → PASS.

- [ ] **Step 3: Add tests one at a time, running each** (inside `describe "#bar_chart"`)

```ruby
    it "scales bar heights to a rounded maximum" do
      heights = chart.all("rect.bar-income").map { _1[:height].to_f }
      expect(heights).to eq([ 90.0, 180.0 ]) # max 200_000 → full plot height of 180
    end

    it "titles every bar with its month, series, and amount" do
      expect(chart).to have_css("rect.bar-income title", text: "Feb income: $2,000.00", visible: :all)
      expect(chart).to have_css("rect.bar-expense title", text: "Jan expenses: $500.00", visible: :all)
    end

    it "labels the axes" do
      texts = chart.all("text.chart-axis", visible: :all).map(&:text)
      expect(texts).to include("Jan", "Feb", "$0", "$1k", "$2k")
    end

    it "is an accessible image" do
      svg = chart.find("svg", visible: :all)
      expect(svg[:role]).to eq("img")
      expect(svg["aria-label"]).to eq("Monthly income and expenses")
      expect(svg[:viewbox] || svg[:viewBox]).to eq("0 0 600 220")
    end

    it "draws axes but no bars when every value is zero" do
      zero = chart(income: [ 0, 0 ], expense: [ 0, 0 ])
      expect(zero).to have_no_css("rect.bar")
      expect(zero).to have_css("line.chart-grid", count: 5, visible: :all)
    end

    it "handles no labels at all" do
      empty = chart(labels: [], income: [], expense: [])
      expect(empty).to have_no_css("rect.bar")
      expect(empty).to have_css("line.chart-grid", count: 5, visible: :all)
    end

    it "fades only the last group when asked" do
      faded = chart(faded_last: true)
      expect(faded).to have_css("rect.faded", count: 1, visible: :all)
      expect(faded).to have_css("rect.faded title", text: "Feb income", visible: :all)
      expect(chart).to have_no_css("rect.faded", visible: :all)
    end
```

and a `describe "#compact_dollars"`:

```ruby
  describe "#compact_dollars" do
    it "abbreviates thousands" do
      expect(helper.compact_dollars(0)).to eq("$0")
      expect(helper.compact_dollars(50_000)).to eq("$500")
      expect(helper.compact_dollars(250_000)).to eq("$2.5k")
      expect(helper.compact_dollars(2_000_000)).to eq("$20k")
    end
  end
```

Note on SVG elements with Capybara: `rect`/`line`/`text` have no layout under rack_test, so pass `visible: :all` wherever an assertion fails only because of visibility.

- [ ] **Step 4: Create `app/assets/stylesheets/components/chart.css`**

```css
.chart { display: block; width: 100%; height: auto; overflow: visible; }
.chart .chart-grid { stroke: var(--chart-grid); stroke-width: 1; }
.chart .chart-axis { fill: var(--muted); font: 10px var(--font-sans); }
.chart .bar-income { fill: var(--chart-income); }
.chart .bar-expense { fill: var(--chart-expense); }
.chart .bar.faded { opacity: .5; }
.chart .bar:hover { opacity: .8; }

.chart-legend { display: flex; gap: var(--space-3); font-size: var(--text-xs); color: var(--muted); font-weight: 400; }
.chart-legend i { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 4px; }
.chart-legend .legend-income { background: var(--chart-income); }
.chart-legend .legend-expense { background: var(--chart-expense); }
```

- [ ] **Step 5: Full suite + rubocop, commit**

```bash
git add app/helpers/charts_helper.rb app/assets/stylesheets/components/chart.css spec/helpers/charts_helper_spec.rb
git commit -m "Add server-rendered SVG bar chart helper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `hbar_list` helper

**Files:**
- Modify: `app/helpers/charts_helper.rb`, `app/assets/stylesheets/components/chart.css`, `spec/helpers/charts_helper_spec.rb`

**Interfaces:**
- Produces: `hbar_list(rows) -> SafeBuffer` — `rows`: `Array<{ label: String, cents: Integer }>`; renders `<ul class="hbar-list">` with one `<li>` per row containing `.hbar-label`, `.hbar-track > .hbar-fill[style="width: N%"]` (N relative to the largest row, one decimal), and `.hbar-value.num` (`Money#to_s`).

- [ ] **Step 1: Write the failing test**

```ruby
  describe "#hbar_list" do
    let(:rows) { [ { label: "Travel", cents: 884_100 }, { label: "Software", cents: 442_050 } ] }
    let(:list) { Capybara.string(helper.hbar_list(rows)) }

    it "scales each bar to the largest row" do
      widths = list.all(".hbar-fill", visible: :all).map { _1[:style] }
      expect(widths).to eq([ "width: 100.0%", "width: 50.0%" ])
    end
  end
```

Run → FAIL.

- [ ] **Step 2: Implement** (public method in `ChartsHelper`, above `private`)

```ruby
  def hbar_list(rows)
    max = rows.map { _1[:cents] }.max.to_i
    items = rows.map do |row|
      percent = max.positive? ? (100.0 * row[:cents] / max).round(1) : 0
      tag.li do
        safe_join([ tag.span(row[:label], class: "hbar-label"),
                    tag.span(tag.span(class: "hbar-fill", style: "width: #{percent}%"), class: "hbar-track"),
                    tag.span(Money.new(row[:cents]).to_s, class: "hbar-value num") ])
      end
    end
    tag.ul(safe_join(items), class: "hbar-list")
  end
```

Run → PASS.

- [ ] **Step 3: Add tests one at a time**

```ruby
    it "shows labels and amounts" do
      expect(list).to have_css("li", count: 2)
      expect(list).to have_css(".hbar-label", text: "Travel")
      expect(list).to have_css(".hbar-value", text: "$8,841.00")
    end

    it "escapes labels" do
      html = helper.hbar_list([ { label: "<b>Meals</b>", cents: 100 } ])
      expect(html).to include("&lt;b&gt;Meals&lt;/b&gt;")
    end

    it "renders an empty list for no rows" do
      expect(Capybara.string(helper.hbar_list([]))).to have_no_css("li")
    end
```

- [ ] **Step 4: Append to `components/chart.css`**

```css
.hbar-list { list-style: none; margin: 0; padding: 0; }
.hbar-list li { display: grid; grid-template-columns: minmax(0, 7rem) 1fr 5.5rem; align-items: center; gap: var(--space-2); margin: 7px 0; font-size: var(--text-sm); }
.hbar-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.hbar-track { height: 8px; background: var(--chart-grid); border-radius: 2px; overflow: hidden; }
.hbar-fill { display: block; height: 100%; background: var(--accent); border-radius: 2px; }
```

- [ ] **Step 5: Full suite + rubocop, commit**

```bash
git add app/helpers/charts_helper.rb app/assets/stylesheets/components/chart.css spec/helpers/charts_helper_spec.rb
git commit -m "Add horizontal bar list helper

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Business overview page

**Files:**
- Create: `app/helpers/overview_helper.rb`, `spec/helpers/overview_helper_spec.rb`, `app/assets/stylesheets/components/{kpi,page_header}.css`
- Modify: `app/controllers/businesses_controller.rb` (`show`), `app/views/businesses/show.html.erb` (rewrite), `spec/requests/businesses_spec.rb` (add `describe "overview"`)

**Interfaces:**
- Consumes: `DateRangeParams#date_range` (existing; defaults to Jan 1..today, swaps reversed ranges), `Reports::CategoryTotals.load`, `Reports::MileageTotals.load(...).deduction_cents`, `Reports::ProfitAndLoss#total_income_cents/#total_expense_cents/#net_profit_cents/#expense_lines` (existing; `Line#actual_cents` is a positive magnitude for expenses), `Reports::MonthlyTotals.load` (Task 7), `bar_chart`/`hbar_list` (Tasks 8–9), `money` (Task 1), `.segmented` (Task 5), `.card`, `.card-title`, `.empty` (Task 2).
- Produces: `period_options(range, today: Date.current) -> Array<[label, { from:, to: }, current?]>` for `Month`, `Quarter`, `YTD`; `share_of_income(part_cents, income_cents) -> String | nil` (`"25% of income"`, nil when income ≤ 0); `month_in_progress?(date, today: Date.current) -> Boolean`.

- [ ] **Step 1: Write the failing helper test**

```ruby
# spec/helpers/overview_helper_spec.rb
require "rails_helper"

RSpec.describe OverviewHelper do
  let(:today) { Date.new(2026, 5, 20) }

  describe "#period_options" do
    it "offers month, quarter, and year to date, marking the one matching the range" do
      options = helper.period_options(Date.new(2026, 4, 1)..today, today:)
      expect(options).to eq([
        [ "Month", { from: "2026-05-01", to: "2026-05-20" }, false ],
        [ "Quarter", { from: "2026-04-01", to: "2026-05-20" }, true ],
        [ "YTD", { from: "2026-01-01", to: "2026-05-20" }, false ]
      ])
    end
  end
end
```

Run → FAIL.

- [ ] **Step 2: Implement**

```ruby
# app/helpers/overview_helper.rb
module OverviewHelper
  def period_options(range, today: Date.current)
    {
      "Month" => today.beginning_of_month..today,
      "Quarter" => today.beginning_of_quarter..today,
      "YTD" => today.beginning_of_year..today
    }.map { |label, period| [ label, { from: period.first.iso8601, to: period.last.iso8601 }, period == range ] }
  end

  def share_of_income(part_cents, income_cents)
    "#{(100.0 * part_cents / income_cents).round}% of income" if income_cents.positive?
  end

  def month_in_progress?(date, today: Date.current) = date.year == today.year && date.month == today.month
end
```

Run → PASS. Add and run one at a time:

```ruby
  it "marks nothing for a custom range" do
    expect(helper.period_options(Date.new(2025, 1, 1)..Date.new(2025, 6, 30), today:).map(&:last)).to all(be false)
  end

  describe "#share_of_income" do
    it "formats a whole percentage" do
      expect(helper.share_of_income(250_000, 1_000_000)).to eq("25% of income")
    end

    it "is nil without income" do
      expect(helper.share_of_income(250_000, 0)).to be_nil
    end
  end

  describe "#month_in_progress?" do
    it "is true only for the current calendar month" do
      expect(helper.month_in_progress?(Date.new(2026, 5, 1), today:)).to be true
      expect(helper.month_in_progress?(Date.new(2025, 5, 31), today:)).to be false
    end
  end
```

- [ ] **Step 3: Write the first failing request test** — add inside `RSpec.describe "Businesses"` in `spec/requests/businesses_spec.rb`:

```ruby
  describe "overview" do
    let(:account) { create(:account, business: business, name: "Checking") }
    let(:consulting) { create(:category, :income, business: business, name: "Consulting") }
    let(:travel) { create(:category, business: business, name: "Travel") }
    let(:page) { Capybara.string(response.body) }

    before { travel_to Time.zone.local(2026, 3, 15, 12) }

    def kpi(label) = page.find(".kpi", text: label)

    it "shows year-to-date income, expenses, and net profit" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 2, 1), amount_cents: 1_000_000)
      create(:transaction, account:, category: travel, posted_on: Date.new(2026, 2, 5), amount_cents: -250_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(kpi("Income")).to have_text("$10,000.00")
      expect(kpi("Expenses")).to have_text("$2,500.00")
      expect(kpi("Expenses")).to have_text("25% of income")
      expect(kpi("Net profit")).to have_css(".pos", text: "$7,500.00")
    end
  end
```

Run: `bundle exec rspec spec/requests/businesses_spec.rb -e overview` → FAIL (no `.kpi`).

- [ ] **Step 4: Implement the controller**

In `app/controllers/businesses_controller.rb` add `include DateRangeParams` below `include BusinessScoped`, and replace `show` with:

```ruby
  def show
    ids = [ @business.id ]
    @report = Reports::ProfitAndLoss.new(
      category_totals: Reports::CategoryTotals.load(business_ids: ids, range: date_range),
      mileage_deduction_cents: Reports::MileageTotals.load(business_ids: ids, range: date_range).deduction_cents
    )
    @top_expenses = @report.expense_lines.sort_by { -_1.actual_cents }.first(5)
    @months = Reports::MonthlyTotals.load(business_ids: ids, year: date_range.last.year, through_month: date_range.last.month)
    inbox = Transaction.for_businesses(@business.id).inbox
    @inbox_count = inbox.count
    @inbox_preview = inbox.order(:posted_on, :id).limit(3)
    @accounts = @business.accounts.active.order(:name)
  end
```

- [ ] **Step 5: Rewrite `app/views/businesses/show.html.erb`**

```erb
<% content_for :title, @business.name %>

<header class="page-header">
  <div>
    <h1><%= @business.name %></h1>
    <p class="subtitle">Taxpayer: <%= @business.person.name %></p>
  </div>
  <nav class="segmented" aria-label="Period">
    <% period_options(date_range).each do |label, range_params, current| %>
      <%= link_to label, business_path(@business, range_params), aria: { current: ("page" if current) } %>
    <% end %>
  </nav>
</header>

<section class="kpis">
  <div class="card kpi">
    <small>Income</small>
    <b><%= money(@report.total_income_cents) %></b>
  </div>
  <div class="card kpi">
    <small>Expenses</small>
    <b><%= money(@report.total_expense_cents) %></b>
    <% if (share = share_of_income(@report.total_expense_cents, @report.total_income_cents)) %>
      <em><%= share %></em>
    <% end %>
  </div>
  <div class="card kpi">
    <small>Net profit</small>
    <b class="<%= "pos" if @report.net_profit_cents.positive? %>"><%= money(@report.net_profit_cents) %></b>
  </div>
</section>

<div class="overview-grid">
  <section class="card">
    <h2 class="card-title">
      Income vs expenses
      <span class="chart-legend"><span><i class="legend-income"></i>Income</span><span><i class="legend-expense"></i>Expenses</span></span>
    </h2>
    <%= bar_chart(
          labels: @months.map { Date::ABBR_MONTHNAMES[_1.month] },
          series: [ { key: "income", name: "Income", values: @months.map(&:income_cents) },
                    { key: "expense", name: "Expenses", values: @months.map(&:expense_cents) } ],
          faded_last: month_in_progress?(date_range.last),
          label: "Monthly income and expenses, #{date_range.last.year}") %>
  </section>

  <section class="card">
    <h2 class="card-title">Top expenses</h2>
    <% if @top_expenses.any? %>
      <%= hbar_list(@top_expenses.map { { label: _1.name, cents: _1.actual_cents } }) %>
    <% else %>
      <div class="empty"><strong>No expenses</strong>Nothing categorized as an expense in this period.</div>
    <% end %>
  </section>
</div>

<section class="card inbox-preview">
  <h2 class="card-title">
    Inbox
    <small><%= pluralize(@inbox_count, "transaction") %> to categorize · <%= link_to "Open inbox →", business_inbox_path(@business) %></small>
  </h2>
  <% if @inbox_preview.any? %>
    <table>
      <tbody>
        <% @inbox_preview.each do |transaction| %>
          <tr>
            <td class="muted"><%= transaction.posted_on.strftime("%b %-d") %></td>
            <td><%= transaction.payee %></td>
            <td class="num"><%= money(transaction.amount_cents) %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% else %>
    <div class="empty"><strong>Inbox zero</strong>Every transaction is categorized.</div>
  <% end %>
</section>

<section class="card">
  <h2 class="card-title">
    Accounts
    <% if current_membership.owner? %><small><%= link_to "Edit business", edit_business_path(@business) %></small><% end %>
  </h2>
  <ul class="plain-list">
    <% @accounts.each do |account| %>
      <li><%= account.name %> <span class="muted">(<%= account.source %>)</span></li>
    <% end %>
  </ul>
</section>
```

Run the overview test → PASS.

- [ ] **Step 6: Add request tests one at a time, running each**

```ruby
    it "shows negative net profit in red parentheses" do
      create(:transaction, account:, category: travel, posted_on: Date.new(2026, 2, 5), amount_cents: -250_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(kpi("Net profit")).to have_css(".neg", text: "($2,500.00)")
      expect(kpi("Net profit")).to have_no_css(".pos")
      expect(kpi("Expenses")).to have_no_text("of income")
    end

    it "charts January through the current month, fading the month in progress" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 1, 10), amount_cents: 500_000)
      create(:transaction, account:, category: consulting, posted_on: Date.new(2026, 3, 10), amount_cents: 300_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      chart = page.find("svg.chart", visible: :all)
      expect(chart.all("text.chart-axis", visible: :all).map(&:text)).to include("Jan", "Feb", "Mar")
      expect(chart).to have_css("rect.bar-income", count: 2, visible: :all)
      expect(chart).to have_css("rect.bar-income.faded title", text: "Mar income: $3,000.00", visible: :all)
    end

    it "uses a custom range from the URL" do
      create(:transaction, account:, category: consulting, posted_on: Date.new(2025, 6, 10), amount_cents: 100_000)
      sign_in_as user_with_role("viewer", business)
      get business_path(business, from: "2025-01-01", to: "2025-06-30")
      expect(kpi("Income")).to have_text("$1,000.00")
      chart = page.find("svg.chart", visible: :all)
      expect(chart["aria-label"]).to eq("Monthly income and expenses, 2025")
      expect(chart).to have_no_css("rect.faded", visible: :all)
      expect(page.find("nav.segmented[aria-label='Period']")).to have_no_css("[aria-current]")
    end

    it "links the period control and marks the selected period" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business, from: "2026-03-01", to: "2026-03-15")
      period = page.find("nav.segmented[aria-label='Period']")
      expect(period).to have_link("Quarter", href: business_path(business, from: "2026-01-01", to: "2026-03-15"))
      expect(period).to have_css('a[aria-current="page"]', text: "Month")
    end

    it "lists the top five expense categories, largest first" do
      %w[A B C D E F].each_with_index do |name, i|
        category = create(:category, business: business, name: "Cat #{name}")
        create(:transaction, account:, category:, posted_on: Date.new(2026, 2, 1), amount_cents: -(i + 1) * 10_000)
      end
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      labels = page.all(".hbar-label").map(&:text)
      expect(labels).to eq([ "Cat F", "Cat E", "Cat D", "Cat C", "Cat B" ])
    end

    it "previews the three oldest inbox transactions" do
      [ 1, 2, 3, 4 ].each { |day| create(:transaction, account:, category: nil, payee: "Payee #{day}", posted_on: Date.new(2026, 2, day)) }
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      preview = page.find(".inbox-preview")
      expect(preview).to have_text("4 transactions to categorize")
      expect(preview.all("tbody tr").map { _1.all("td")[1].text }).to eq([ "Payee 1", "Payee 2", "Payee 3" ])
      expect(preview).to have_link("Open inbox →", href: business_inbox_path(business))
    end

    it "renders an empty business with zeros and empty states" do
      sign_in_as user_with_role("viewer", business)
      get business_path(business)
      expect(response).to have_http_status(:ok)
      expect(kpi("Income")).to have_text("$0.00")
      expect(page).to have_no_css("svg.chart rect.bar", visible: :all)
      expect(page).to have_text("No expenses")
      expect(page).to have_text("Inbox zero")
    end

    it "keeps the account list and owner-only edit link" do
      account
      sign_in_as user_with_role("owner", business)
      get business_path(business)
      expect(page).to have_text("Checking")
      expect(page).to have_link("Edit business", href: edit_business_path(business))
    end
```

The existing `"shows a business to a viewer"` test keeps passing (the name is still in the page).

- [ ] **Step 7: Create `components/page_header.css` and `components/kpi.css`, plus overview layout**

`app/assets/stylesheets/components/page_header.css`:

```css
.page-header { display: flex; justify-content: space-between; align-items: flex-end; gap: var(--space-4); flex-wrap: wrap; margin-bottom: var(--space-5); }
.page-header h1 { margin: 0; }
.page-header .subtitle { margin: 2px 0 0; color: var(--muted); }
```

`app/assets/stylesheets/components/kpi.css`:

```css
.kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: var(--space-3); margin-bottom: var(--space-3); }
.kpis .card { margin: 0; }
.kpi small { display: block; color: var(--muted); font-size: var(--text-xs); }
.kpi b { display: block; margin-top: 2px; font-family: var(--font-mono); font-size: var(--text-2xl); font-weight: 500; letter-spacing: -0.02em; font-variant-numeric: tabular-nums; }
.kpi em { font-style: normal; font-size: var(--text-xs); color: var(--muted); }

.overview-grid { display: grid; grid-template-columns: minmax(0, 1.6fr) minmax(0, 1fr); gap: var(--space-3); margin-bottom: var(--space-3); }
.overview-grid .card { margin: 0; }
@media (max-width: 1000px) { .overview-grid { grid-template-columns: minmax(0, 1fr); } }

.plain-list { list-style: none; margin: 0; padding: 0; }
.plain-list li { padding: 3px 0; }
```

- [ ] **Step 8: Full suite + rubocop, commit**

```bash
git add app/helpers/overview_helper.rb app/controllers/businesses_controller.rb app/views/businesses/show.html.erb app/assets/stylesheets/components spec
git commit -m "Turn the business page into an overview with KPIs and charts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Contrast check of the palette

**Files:**
- Create: `spec/config/design_tokens_spec.rb`
- Modify (only if a ratio fails): `app/assets/stylesheets/tokens.css`

**Interfaces:**
- Consumes: `tokens.css` `light-dark(#xxxxxx, #xxxxxx)` declarations (Task 2).

- [ ] **Step 1: Write the test**

```ruby
# spec/config/design_tokens_spec.rb
require "rails_helper"

RSpec.describe "Design tokens" do
  TOKENS = File.read(Rails.root.join("app/assets/stylesheets/tokens.css"))
    .scan(/--([\w-]+):\s*light-dark\((#\h{6}),\s*(#\h{6})\)/)
    .to_h { |name, light, dark| [ name, { light:, dark: } ] }

  def luminance(hex)
    hex.delete("#").scan(/../).map { _1.to_i(16) / 255.0 }
      .map { _1 <= 0.03928 ? _1 / 12.92 : ((_1 + 0.055) / 1.055)**2.4 }
      .then { |r, g, b| 0.2126 * r + 0.7152 * g + 0.0722 * b }
  end

  def contrast(a, b)
    hi, lo = [ luminance(a), luminance(b) ].sort.reverse
    (hi + 0.05) / (lo + 0.05)
  end

  %w[fg muted accent neg pos warn].each do |text|
    %w[bg surface].each do |background|
      %i[light dark].each do |mode|
        it "#{text} on #{background} meets WCAG AA in #{mode} mode" do
          expect(contrast(TOKENS.dig(text, mode), TOKENS.dig(background, mode))).to be >= 4.5
        end
      end
    end
  end

  it "keeps text on accent-soft and on-accent readable" do
    %i[light dark].each do |mode|
      expect(contrast(TOKENS.dig("accent-fg", mode), TOKENS.dig("accent-soft", mode))).to be >= 4.5
      expect(contrast(TOKENS.dig("on-accent", mode), TOKENS.dig("accent", mode))).to be >= 4.5
    end
  end
end
```

Rubocop may flag the top-level constant inside the block (`Lint/ConstantDefinitionInBlock`); if so use `let(:tokens)` with the same expression and reference `tokens` instead.

- [ ] **Step 2: Run it** — `bundle exec rspec spec/config/design_tokens_spec.rb`. For every failure, darken (light mode) or lighten (dark mode) that token's value in small steps within the same hue until the ratio is ≥ 4.5, re-running after each change. Likely candidates: `--pos` and `--warn` in light mode, `--neg` light. Keep `--chart-income` = `var(--accent)`.

- [ ] **Step 3: Full suite + commit**

```bash
git add spec/config/design_tokens_spec.rb app/assets/stylesheets/tokens.css
git commit -m "Check palette contrast against WCAG AA

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Visual verification, cleanup, PR

**Files:** none planned; fix-ups as found.

- [ ] **Step 1: Seed demo data and start the app**

```bash
bin/rails demo:reset   # wipes the development DB and seeds demo data — dev only
bin/rails server -p 3100   # run in background
```

Find demo login credentials in `lib/demo_seeder.rb` (or `lib/tasks/demo.rake`). 2FA codes come from the seeded user's TOTP: `bin/rails runner 'puts User.find_by!(email_address: "<email>").totp.now'`.

- [ ] **Step 2: Screenshot in light and dark** (Playwright MCP tools, viewport 1400×900; switch theme with the sidebar toggle): sign-in page, business overview, inbox, transactions, P&L, a form (new rule), and the overview at 600px width with the drawer open. Look for: unreadable text, broken alignment of `.num` columns, overflowing tables, unstyled leftovers from the old CSS, layout jumps between themes. Fix any problems in CSS (no test needed for pure CSS) and re-screenshot.

- [ ] **Step 3: Final checks**

```bash
bundle exec rspec          # 0 failures, no extra output
bundle exec rubocop        # no offenses
git checkout Gemfile.lock  # if Bundler touched it
grep -rn "business_nav\|site-header\|site-nav" app spec   # nothing
```

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin design-system
gh pr create --base main --title "Design system: ink & indigo, sidebar shell, dark mode, overview charts" --body-file <(cat <<'EOF'
## Summary
- Design tokens with light/dark/system themes (`light-dark()` + `color-scheme`), switchable from the sidebar; preference stored in a `theme` cookie and rendered server-side (no flash).
- Sidebar shell with business switcher; mobile drawer; centered card for signed-out pages.
- IBM Plex Sans / Mono, self-hosted.
- Element-first CSS so existing and in-flight views are styled without markup changes.
- Negative amounts in red parentheses on screen (CSV exports unchanged).
- Business page is now an overview: KPIs, monthly income vs expenses (server-rendered SVG), top expenses, inbox preview.
- `business_nav` removed entirely (helper, partial, CSS, call sites).

Spec: `docs/superpowers/specs/2026-10-10-design-system-design.md`
Plan: `docs/superpowers/plans/2026-10-10-design-system.md`

## Rebasing the open PRs (#6 → #7 → #8/#9)
Move each PR's `application.css` additions into the matching file, move its new nav links into `layouts/_sidebar.html.erb`, and delete its `<%= business_nav @business %>` lines.

## Screenshots
(attach light/dark screenshots from Step 2)

## Test plan
- [ ] `bundle exec rspec` green
- [ ] Visual pass in light and dark, desktop and 600px

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)
```
