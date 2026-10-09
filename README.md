# goodbooks

Self-hosted bookkeeping for a freelancing household: income and expenses per business, CSV imports, a rules-driven categorization inbox, invoice tracking with payments linked to deposits, mileage, P&L and Schedule C reports, and role-based sharing with your accountant. Design: `docs/superpowers/specs/2026-10-05-goodbooks-design.md` (invoices: `docs/superpowers/specs/2026-10-06-goodbooks-invoices-design.md`).

The household owner can set up a **Personal** book from the dashboard for the joint checking account. It has its own categories, rules, inbox, a spending report, and a weekly tithe page (10% of tithable deposits, Sunday–Saturday, payments applied oldest week first). Only the household owner and linked spouse can see it; the accountant cannot. Design: `docs/superpowers/specs/2026-10-06-goodbooks-tithing-design.md`.

**Sales tax (Tennessee).** An owner turns it on from a business's **Sales tax** page (TN account number, filing frequency, default rate, start date). Income categories are marked taxable, exempt, or not a sale. Deposits can carry the card processor's fee (Stripe) and the sales tax from the payout report, and a "tax-inclusive" button backs the tax out at the default rate. Invoices can include sales tax, which is shared out to the deposits that pay them. Each filing period shows gross, exempt, and taxable sales, tax collected, remitted, and balance owed, with its due date (the 20th of the following month, rolled past weekends and the TN holidays that can fall on it, computed for any year). Reports count income net of sales tax and gross of fees, with fees under Merchant fees.

## Development

```bash
bin/setup               # install gems, prepare the database
bin/rails demo:reset    # load demo data; prints logins and the TOTP secret
bin/dev                 # http://localhost:3000
bundle exec rspec       # test suite
```

## Deploying on a home server

1. Copy `.env.example` to `.env`; set `RAILS_MASTER_KEY` (contents of `config/master.key`).

2. First-run setup, locally, BEFORE exposing anything:
   - Set `APP_HOST=localhost` in `.env`.
   - Run `docker compose up -d --build`.
   - On the server itself, open `http://localhost:3000` in Chrome or Firefox (they treat localhost as secure, which the app's secure cookies need).
   - Create the household and enroll in 2FA.
   - **Warning:** the first visitor to an un-set-up install can claim it — that's why this happens before the tunnel exists.
   - *If the server is headless*, use an SSH port-forward from your laptop: `ssh -L 3000:localhost:3000 you@server`, then open `http://localhost:3000` on the laptop.

3. Set `APP_HOST` to your public hostname (it must exactly match the hostname people type — don't override the Host header in the tunnel), then `docker compose up -d`.

4. Expose port 3000 through the tunnel. TLS terminates at the tunnel.
   - **Cloudflare Tunnel:** `cloudflared tunnel create goodbooks`, route `APP_HOST` to `http://localhost:3000`, run `cloudflared tunnel run goodbooks` (or install it as a service).
   - **Tailscale Funnel:** `tailscale funnel --bg 3000`; set `APP_HOST` to your `*.ts.net` name.

5. Visit `https://APP_HOST` and sign in.

### Invite links

To invite others to the household, go to **Invites** and create an invite link. Share it like a password — whoever holds the link can join, and the email field is only a prefill suggestion. Invite links expire after 7 days, can be used once, and can be revoked from the **Invites** page at any time.

## Updating

```bash
git pull && docker compose up -d --build
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

The SQLite backups are useless without `config/master.key`: it decrypts the stored 2FA secrets, so a restored database without it cannot sign anyone in. Store `config/master.key` and `.env` offsite, separately from the database copies. Restoring needs both.

## Each tax year

Household owner → Tax parameters → add the year's IRS standard mileage rate once the IRS publishes it.
