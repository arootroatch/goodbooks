# goodbooks

Self-hosted bookkeeping for a freelancing household: income and expenses per business, CSV imports, a rules-driven categorization inbox, invoice tracking with payments linked to deposits, mileage, P&L and Schedule C reports, and role-based sharing with your accountant. Design: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` (invoices: `docs/superpowers/specs/2026-10-06-goodbooks-invoices-design.md`).

The household owner can set up a **Personal** book from the dashboard for the joint checking account. It has its own categories, rules, inbox, a spending report, and a weekly tithe page (10% of tithable deposits, Sunday–Saturday, payments applied oldest week first). Only the household owner and linked spouse can see it; the accountant cannot. Design: `docs/superpowers/specs/2026-10-06-goodbooks-tithing-design.md`.

**Sales tax (Tennessee).** An owner turns it on from a business's **Sales tax** page (TN account number, filing frequency, default rate, start date). Income categories are marked taxable, exempt, or not a sale. Deposits can carry the card processor's fee (Stripe) and the sales tax from the payout report, and a "tax-inclusive" button backs the tax out at the default rate. Invoices can include sales tax, which is shared out to the deposits that pay them. Each filing period shows gross, exempt, and taxable sales, tax collected, remitted, and balance owed, with its due date (the 20th of the following month, rolled past weekends and the TN holidays that can fall on it, computed for any year). Reports count income net of sales tax and gross of fees, with fees under Merchant fees.

**Federal estimated tax.** The **Taxes** page (household access) estimates each quarter's federal payment for a married-filing-jointly household of sole proprietors: SE tax per person, Additional Medicare, AGI with half SE tax, self-employed health insurance, and retirement contributions, the standard deduction, a simplified QBI deduction, and the brackets. It shows the regular installment (against the lesser of 90% of projected tax and the 100%/110% prior-year safe harbor) beside the annualized installment (Form 2210 Schedule AI) and recommends the lesser, with every intermediate number in a worksheet. Payments are recorded by picking the IRS debit from the bank feed. Home office (simplified or regular) fills Schedule C line 30. The federal figures live in **Tax parameters** (2026 seeded), and the IRS payment link in **Household** settings. It's an estimate; verify with your accountant.

## Development

```bash
bin/setup               # install gems, prepare the database
bin/rails demo:reset    # load demo data; prints logins and the TOTP secret
bin/dev                 # http://localhost:3000
bundle exec rspec       # test suite
```

## Deploying on a home server

1. Put `config/master.key` on the server (copy it from your dev machine; it is gitignored). Compose mounts it read-only into the container.

2. First-run setup, locally, BEFORE exposing anything:
   - In `docker-compose.yml`, set `APP_HOST: localhost`. The app refuses to start while it is blank.
   - Run `docker compose up -d --build`.
   - On the server itself, open `http://localhost:3000` in Chrome or Firefox (they treat localhost as secure, which the app's secure cookies need).
   - Create the household and enroll in 2FA.
   - **Warning:** the first visitor to an un-set-up install can claim it — that's why this happens before the tunnel exists.
   - *If the server is headless*, use an SSH port-forward from your laptop: `ssh -L 3000:localhost:3000 you@server`, then open `http://localhost:3000` on the laptop.

3. In `docker-compose.yml`, set `APP_HOST` to your public hostname (it must exactly match the hostname people type — don't override the Host header in the tunnel), then `docker compose up -d`.

4. Expose port 3000 through the tunnel. TLS terminates at the tunnel.
   - **Cloudflare Tunnel:** `cloudflared tunnel create goodbooks`, route `APP_HOST` to `http://localhost:3000`, run `cloudflared tunnel run goodbooks` (or install it as a service).
   - **Tailscale Funnel:** `tailscale funnel --bg 3000`; set `APP_HOST` to your `*.ts.net` name.

5. Visit `https://APP_HOST` and sign in.

### Invite links

To invite others to the household, go to **Invites** and create an invite link. Share it like a password — whoever holds the link can join, and the email field is only a prefill suggestion. Invite links expire after 7 days, can be used once, and can be revoked from the **Invites** page at any time.

### Bank feeds (Plaid)

Set `PLAID_CLIENT_ID`, `PLAID_SECRET`, and `PLAID_ENV` (`sandbox` or `production`) to connect banks through Plaid.
Without all three, production hides every Plaid screen; development uses a fake "Demo Bank" so the screens can be tried
without keys (`bin/rails demo:reset` connects it to Sound Roots Productions and Joint Checking).

- **Banks** (sidebar, under Settings, for anyone who owns a book) → **Connect a bank** opens Plaid Link. Afterwards each bank account
  becomes a new account in a book you own, feeds an existing manual or CSV account (pick "Existing account"; a blank
  "Sync from" starts after its latest transaction), or is skipped.
- Transactions sync daily at 4am, when Plaid's webhook says there are updates, and on **Sync now**. Pending
  transactions are skipped until they post.
- Plaid and CSV dedupe against each other: a row with the same amount within 3 days is claimed rather than duplicated,
  so CSV upload stays available on Plaid accounts as a fallback.
- If the bank removes or changes a transaction you had categorized or linked to an invoice, it shows under
  **Needs review** in the inbox: **Keep** or **Exclude**.
- Webhooks are received at `https://APP_HOST/plaid/webhooks` and verified with Plaid's signature; they need the app
  reachable from the internet (the tunnel). Without them the daily sync still runs.
- If the bank asks you to sign in again, the dashboard shows **Reconnect**.

To try Plaid's sandbox: create a free account at dashboard.plaid.com, copy the sandbox keys from Developers → Keys,
start the app with `PLAID_CLIENT_ID=… PLAID_SECRET=… PLAID_ENV=sandbox bin/dev`, connect "First Platypus Bank", and
sign in with `user_good` / `pass_good`.

## Updating

```bash
git pull --autostash && docker compose up -d --build
```

## Logs

```bash
docker compose logs -f app
```

Data lives in the `goodbooks_storage` Docker volume (SQLite databases, uploads, backups).

## Backups

A nightly job (03:00) writes `storage/backups/goodbooks-YYYY-MM-DD.sqlite3` and keeps 14 copies. Copy them offsite:

```bash
docker run --rm -v goodbooks_storage:/data -v "$PWD":/out alpine \
  sh -c 'cp /data/backups/*.sqlite3 /out/'
```

The SQLite backups are useless without `config/master.key`: it decrypts the stored 2FA secrets, so a restored database without it cannot sign anyone in. Store `config/master.key` offsite, separately from the database copies. Restoring needs both.

## Each tax year

Household owner → Tax parameters → add the year's IRS standard mileage rate once the IRS publishes it.
