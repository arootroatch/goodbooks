# goodbooks

Self-hosted bookkeeping for a freelancing household: income and expenses per business, CSV imports, a rules-driven categorization inbox, mileage, P&L and Schedule C reports, and role-based sharing with your accountant. Design: `docs/superpowers/specs/2026-10-05-goodbooks-design.md`.

## Development

```bash
bin/setup               # install gems, prepare the database
bin/rails demo:reset    # load demo data; prints logins and the TOTP secret
bin/dev                 # http://localhost:3000
bundle exec rspec       # test suite
```

## Deploying on a home server

1. Copy `.env.example` to `.env`. Set `RAILS_MASTER_KEY` (from `config/master.key`) and `APP_HOST` (the public hostname).
2. `docker compose up -d --build`
3. Complete first-run setup (create the household and enroll in 2FA) on your local network BEFORE exposing the tunnel — the first visitor to an un-set-up install can claim it.
4. Expose port 3000 through a tunnel. TLS terminates at the tunnel.
   - **Cloudflare Tunnel:** `cloudflared tunnel create goodbooks`, route `APP_HOST` to `http://localhost:3000`, run `cloudflared tunnel run goodbooks` (or install it as a service).
   - **Tailscale Funnel:** `tailscale funnel --bg 3000`; set `APP_HOST` to your `*.ts.net` name.

Data lives in the `goodbooks_storage` Docker volume (SQLite databases, uploads, backups).

## Backups

A nightly job (03:00) writes `storage/backups/goodbooks-YYYY-MM-DD.sqlite3` and keeps 14 copies. Copy them offsite:

```bash
docker run --rm -v goodbooks_storage:/data -v "$PWD":/out alpine \
  sh -c 'cp /data/backups/*.sqlite3 /out/'
```

## Each tax year

Household owner → Tax parameters → add the year's IRS standard mileage rate once the IRS publishes it.
