# goodbooks

Self-hosted bookkeeping for a freelancing household. One install holds one household: the businesses it runs, a
personal book for the joint account, and the people who help with the books, such as a spouse or an accountant. It
replaces the parts of QuickBooks a sole-proprietor household actually uses, and runs as a single Docker container on a
home server.

- **Books.** Income and expenses per business, from manual entry, CSV imports, or bank feeds through Plaid. A
  rules-driven inbox categorizes new transactions; mileage, P&L and Schedule C reports.
- **Invoices.** Tracks invoices you send from elsewhere: payments linked to the deposits that paid them, aging, PDFs.
- **Personal book.** The joint checking account, with its own categories, rules and inbox, a spending report, and a
  weekly tithe ledger (10% of tithable deposits). Only the household owner and their spouse see it.
- **Sales tax (Tennessee).** Taxable and exempt income, Stripe processor fees, filing periods with due dates, and
  remittances.
- **Federal estimated tax.** Quarterly estimates for a married-filing-jointly household of sole proprietors, with
  every number shown in a worksheet. It's an estimate; verify with your accountant.
- **Goals.** Payment goals (for example, paying back a loan) and savings goals filled from an account's balance.
- **Sharing.** Invite links, per-book roles (owner, editor, viewer), and mandatory two-factor sign-in for everyone.

Design documents live in `docs/superpowers/specs/`, starting with `2026-10-05-goodbooks-design.md`.

## What you need

- A server that stays on, running Docker with Compose v2. Images are published for `amd64` and `arm64`, so a
  64-bit Raspberry Pi works.
- A way to reach it over HTTPS. The app only works over HTTPS (or `localhost`). The steps below use
  [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) or
  [Tailscale Funnel](https://tailscale.com/kb/1223/funnel), so you don't open any ports or manage certificates.
- An authenticator app (1Password, Google Authenticator, and so on) for every person who signs in.
- Optional: a [Plaid](https://plaid.com) account for automatic bank feeds. Without it, import CSVs from your bank.

## Install

1. **Get the compose file.** Make a folder on the server and copy [`docker-compose.yml`](docker-compose.yml) into it,
   either by pasting it into an editor or with
   `curl -O https://raw.githubusercontent.com/arootroatch/goodbooks/main/docker-compose.yml`. This one file is your
   whole configuration. It will hold your secrets, so make it private: `chmod 600 docker-compose.yml`.

2. **Generate your secrets.** Run this once and paste the four lines it prints over the matching blank lines in
   `docker-compose.yml`:

   ```bash
   for name in SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY \
               ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT; do
     echo "      $name: \"$(openssl rand -hex 64)\""
   done
   ```

   **Never change these once the app is in use, and keep a copy offsite.** The encryption keys unlock everyone's
   two-factor secrets and bank connections. Lose them and nobody can sign in, even from a backup. See
   [Backups](#backups).

3. **Set the time zone.** `TIME_ZONE` takes a Rails zone name such as `Eastern Time (US & Canada)` or
   `Pacific Time (US & Canada)`. "Today" rolls over at local midnight in that zone.

4. **Set up the household before exposing anything.** The first person to open a new install claims it, so do this
   while it is reachable only from the server:
   - Set `APP_HOST: "localhost"` and run `docker compose up -d`.
   - On the server, open `http://localhost:3000` in a browser. With `APP_HOST` set to `localhost` the app serves
     plain HTTP; with any other hostname it requires HTTPS. *If the server is headless*, forward the port from your laptop with
     `ssh -L 3000:localhost:3000 you@server` and open `http://localhost:3000` there.
   - Create the household: its name, your name, email and password (12 characters or more), and your spouse's name
     if you have one. Then scan the QR code with your authenticator app and **save the recovery codes** it shows.

5. **Set your public hostname.** Change `APP_HOST` to the hostname people will type, such as `books.example.com`, and
   run `docker compose up -d` again. It must match exactly, so don't have the tunnel rewrite the `Host` header.

6. **Expose port 3000 through a tunnel.** TLS ends at the tunnel; the app listens only on `127.0.0.1:3000`.
   - **Cloudflare Tunnel:** `cloudflared tunnel create goodbooks`, route `APP_HOST` to `http://localhost:3000`, then
     run `cloudflared tunnel run goodbooks` or install it as a service.
   - **Tailscale Funnel:** `tailscale funnel --bg 3000`, and set `APP_HOST` to your `*.ts.net` name.

7. Visit `https://APP_HOST` and sign in.

If the container keeps restarting, run `docker compose logs app`. A blank `APP_HOST` or secret stops the app at boot
with a message naming the setting to fill in.

## First steps

- **Add your businesses** from the dashboard (**New business**). Each one starts with the Schedule C categories.
- **Add accounts** to each business, then import a CSV export from your bank or connect it through Plaid.
- **Set up the personal book** from the dashboard if you want the joint account and the tithe tracked.
- **Invite people** (below). A spouse usually gets owner or editor on the books they help with; an accountant gets
  viewer on the business books only.
- **Check Tax parameters and Household settings** for the federal figures and your IRS payment link.

### Invite links

To invite someone, go to **Invites** and create an invite link for the books and role they should have. Share it
like a password: whoever holds the link can join, and the email field is only a prefill suggestion. Invite links
expire after 7 days, can be used once, and can be revoked from **Invites** at any time. goodbooks sends no email;
you send the link yourself.

## Bank feeds (Plaid)

Plaid is optional. Without it, production hides every Plaid screen and you import CSVs instead.

1. Create an account at [dashboard.plaid.com](https://dashboard.plaid.com) and request Production access for the
   Transactions product. Plaid reviews the request; until it is approved, only Sandbox keys work.
2. Copy the client ID and secret from **Developers → Keys** into `PLAID_CLIENT_ID` and `PLAID_SECRET`, set
   `PLAID_ENV: "production"` (or `"sandbox"` to try it with Plaid's test banks), and run `docker compose up -d`. All
   three must be set; a typo in `PLAID_ENV` turns Plaid off and logs why.
3. Anyone who owns a book can then go to **Banks** (under Settings) → **Connect a bank**. Each bank account becomes
   a new account in a book they own, feeds an existing manual or CSV account (pick "Existing account"; a blank "Sync
   from" starts after its latest transaction), or is skipped.

How it behaves:

- Transactions sync once a day, whenever Plaid's webhook reports updates, and on **Sync now**. Pending
  transactions are skipped until they post.
- Webhooks arrive at `https://APP_HOST/plaid/webhooks` and are verified with Plaid's signature, so they need the
  tunnel. Without them the daily sync still runs.
- Plaid and CSV rows dedupe against each other: a row with the same amount within 3 days is claimed rather than
  duplicated, so CSV upload stays available on Plaid accounts as a fallback.
- If the bank removes or changes a transaction you had categorized or linked to an invoice, it shows under
  **Needs review** in the inbox, where you can **Keep** or **Exclude** it.
- If the bank asks you to sign in again, the dashboard shows **Reconnect**.

## Backups

Everything lives in the `goodbooks_storage` Docker volume: the SQLite databases, uploaded files (invoice PDFs and
CSV imports), and the nightly backups.

**Nightly snapshots.** Every night the app writes a consistent copy of the main database to
`backups/goodbooks-YYYY-MM-DD.sqlite3` in the volume and keeps the latest 14. The household owner's **Backups** page
shows when the last one ran, warns if one is missed, takes one on demand, downloads any of them, and sets how many to
keep. That protects against mistakes, not against losing the server's disk.

**Offsite copies.** Copy the volume somewhere else regularly, for example from cron to a NAS or a synced folder:

```bash
docker run --rm -v goodbooks_storage:/data:ro -v /path/to/offsite:/out alpine \
  sh -c 'tar czf /out/goodbooks-$(date +%F).tgz -C /data .'
```

Also keep a copy of `docker-compose.yml` offsite, somewhere separate from the archives (a password manager works).
**A backup is useless without the keys in that file**: they decrypt the stored two-factor secrets, so a restored
database without them cannot sign anyone in.

**Restoring.** Restore from a nightly snapshot in `backups/`, not from the live databases, which an archive may have
caught mid-write. Anything entered after that snapshot is lost, and bank transactions sync again on the next run. Put
the snapshot's date in the command:

```bash
docker compose stop app
docker run --rm -v goodbooks_storage:/data alpine sh -c '
  cp /data/backups/goodbooks-2026-10-14.sqlite3 /data/production.sqlite3 &&
  rm -f /data/production.sqlite3-wal /data/production.sqlite3-shm &&
  chown 1000:1000 /data/production.sqlite3'
docker compose start app
```

The **Backups** page shows the same command with a chosen snapshot's date filled in.

**Moving to a new server.** Copy your `docker-compose.yml` over, unpack an offsite archive into a new volume (this
brings back the uploaded files and the snapshots), run the `docker run` restore command above, then
`docker compose up -d`:

```bash
docker volume create goodbooks_storage
docker run --rm -v goodbooks_storage:/data -v /path/to/offsite:/in alpine \
  sh -c 'tar xzf /in/goodbooks-2026-10-14.tgz -C /data'
```

## Updating

```bash
docker compose pull && docker compose up -d
```

The app migrates its database on start. Each release on GitHub is published as `ghcr.io/arootroatch/goodbooks` with
tags for the exact version (`1.4.0`), the minor line (`1.4`), and `latest`. To stay on a version, put its tag in
`image:` instead of `latest`. If a release changes the template, compare your `docker-compose.yml` against the new
[`docker-compose.yml`](docker-compose.yml) and copy over anything new; your settings and secrets stay as they are.

## Logs and troubleshooting

```bash
docker compose logs -f app
```

Docker keeps at most 50 MB of app logs (five 10 MB files), so older lines roll off. Unhandled errors are also
recorded on the **Errors** page (household owner only), grouped by error.

- **The container keeps restarting:** the log names the setting that is blank, such as `APP_HOST` or a secret.
- **A blank page (403) instead of the sign-in page:** the hostname in the browser doesn't match `APP_HOST`. The
  log says `Blocked hosts:` followed by the hostname it received.
- **Health check:** `curl -s http://localhost:3000/up` returns 200 when the app is up.

## Locked out

- **Lost authenticator:** sign in with one of your recovery codes. Each works once.
- **Lost password or every recovery code:** from the server, reset it (replace the email address and password):

  ```bash
  docker compose exec app bin/rails runner \
    'User.find_by!(email_address: "you@example.com").update!(password: "a new long password")'
  ```

  To make someone set up two-factor sign-in again on their next sign-in:

  ```bash
  docker compose exec app bin/rails runner \
    'User.find_by!(email_address: "you@example.com").update!(otp_enabled_at: nil)'
  ```

## Each tax year

goodbooks ships the federal figures for the years it knows about. When a new year starts, the household owner opens
**Tax parameters**, adds the year (brackets, standard deduction, Social Security wage base, and so on, from the IRS),
and adds the IRS standard mileage rate once it's published. The **Taxes** page says when a year's figures are
incomplete.

## Development

```bash
bin/setup               # install gems, prepare the database
bin/rails demo:reset    # load demo data; prints logins and the TOTP secret
bin/dev                 # http://localhost:3000
bundle exec rspec       # test suite
```

Development uses a fake "Demo Bank" in place of Plaid, so the bank screens work without keys (`bin/rails demo:reset`
connects it to two demo accounts). To try Plaid's real sandbox, create a free account at dashboard.plaid.com, copy the
sandbox keys from **Developers → Keys**, run `PLAID_CLIENT_ID=… PLAID_SECRET=… PLAID_ENV=sandbox bin/dev`, connect
"First Platypus Bank", and sign in with `user_good` / `pass_good`.

### Releasing

Push a version tag from `main`:

```bash
git tag v1.4.0 && git push origin v1.4.0
```

The Release workflow runs the full CI suite, then builds the image for `amd64` and `arm64` on native runners and
pushes it to `ghcr.io/arootroatch/goodbooks` as `1.4.0`, `1.4` and `latest`. GHCR packages start out private, so
after the first release open the package's settings on GitHub and set its visibility to **Public**. Otherwise
servers need `docker login ghcr.io` to pull it.
