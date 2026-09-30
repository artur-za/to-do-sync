# Full deployment: Vercel + PostgreSQL

This mode hosts the PHP API, Telegram webhook, reminder endpoint and Mini App on Vercel. It uses the pinned community runtime `vercel-php@0.9.0` (PHP 8.5, pdo_pgsql). The same server logic is used on SSH and Vercel. SQLite and local file locks are never used for Vercel data.

## Resources the agent must configure

1. Vercel project linked to this repository, root directory `.`, framework Other, Node 22 or runtime-compatible default. Use the root `vercel.json`.
2. Dedicated persistent PostgreSQL database (e.g. Neon via Vercel Marketplace), TLS connection string. Existing integration can be reused only if its database/schema is reserved for this installation. Tables are created automatically; use a separate database per bot. Transaction-pooled connections are supported: synchronization/outbox locks are transaction-scoped PostgreSQL advisory locks, not session locks or `/tmp` files.
3. Stable public Production domain. Vercel's normal generated production domain is sufficient; custom domain is optional. It must be accessible to Telegram and unauthenticated clients for the public entrypoints. Keep application auth enabled; do not expose DB credentials.
4. Every-minute scheduler: **Vercel Pro cron** or an external scheduler capable of sending an Authorization header. Hobby's built-in daily-only cron is not sufficient. Do not upgrade billing without authorization.

A Vercel token alone may not authorize provisioning an external database/integration. If no database is available, connect/create one through the user's authorized Marketplace/provider account or request that missing access. Never pretend `/tmp` is persistent storage.

## Environment

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL URI including credentials and `sslmode=require` (or provider's verified stronger TLS mode) |
| `BOT_TOKEN` | BotFather token, server only |
| `BOT_USERNAME` | Public bot username, no `@`; used by build to create Mini App config |
| `OWNER_ID` | Verified numeric Telegram user ID |
| `PUBLIC_URL` | Stable Production base URL, e.g. `https://my-todo.vercel.app` |
| `SYNC_TOKEN` | Independent random 256-bit Mac Bearer key |
| `WEBHOOK_SECRET` | Independent random 256-bit Telegram webhook secret |
| `CRON_SECRET` | Independent random 256-bit scheduler Bearer key |
| `TIMEZONE` | `Europe/Moscow` by default |

Store secrets only in Vercel Production environment and ignored local files. Do not share production bot/database credentials with Preview environments. Preview deployments need a separate test bot/database and a scheduler disabled by default. `PUBLIC_URL` is explicit: do not infer the bot callback URL from an arbitrary preview URL.

Helper: copy `deploy/settings.example.json` to `.deploy/settings.json`, fill fields and add `database_url`. Set transport to webhook. Then:

```sh
umask 077
python3 deploy/vercel-env.py --settings .deploy/settings.json --output .deploy/vercel-env.json
vercel link
```

Upload each JSON value through the authenticated Vercel API/MCP or CLI stdin, not shell arguments. Example Python snippet (prints only names/status; run from project root after linking):

```python
import json, subprocess
from pathlib import Path
values = json.loads(Path('.deploy/vercel-env.json').read_text())
for name, value in values.items():
    result = subprocess.run(['vercel', 'env', 'add', name, 'production'],
                            input=str(value), text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(f'{name}: could not add; inspect existing variable without printing its value')
    print(name + ': configured')
```

On updates preserve existing values. Use the provider's update operation rather than deleting/regenerating keys. New environment values need a new Production deployment.

## Deploy and configure Telegram

```sh
vercel deploy --prod
python3 deploy/smoke.py https://my-todo.vercel.app
python3 deploy/telegram.py --settings .deploy/settings.json --configure --vercel
```

Build creates only public Mini assets under `public/`; private PHP code is bundled into functions, not static files. `.vercelignore` excludes secrets, data and Mac artifacts. `/index.php` rewrites to `/api/index.php` for Mac compatibility; Mini uses `/api/index.php?route=mini-sync`.

Webhook: `https://my-todo.vercel.app/api/index.php?route=webhook`. The setup helper installs the secret header, keeps pending updates, and configures the «Открыть» menu button to `/mini/`. Stop any old polling worker before switching. Main Mini App in BotFather remains a separate owner-side setting; see DEPLOY.md.

## Turn on the minute scheduler

Root vercel.json intentionally does not assume a paid plan, so importing it on Hobby does not fail. **Scheduling is a mandatory deployment step**, not optional polish.

**Pro:** add this top-level property to vercel.json and redeploy Production:

```json
"crons": [{"path": "/api/cron.php", "schedule": "* * * * *"}]
```

Vercel automatically sends `Authorization: Bearer <CRON_SECRET>` when that environment variable is set.

**Hobby:** create an every-minute job in the user's authorized external scheduler. URL `/api/cron.php`, method GET, header `Authorization: Bearer <CRON_SECRET>`. Store the key as a scheduler secret; never put it in URL/query. The endpoint rejects missing/wrong auth. Confirm the scheduler actually runs; do not substitute a daily job.

`api/cron.php` queues due reminders and Today at 09:00 Moscow, then drains a bounded part of the durable outbox. Repeated/overlapping calls don't duplicate queue entries. Delivery retries use PostgreSQL state; there is no in-memory queue or long-polling process to keep alive. For a personal bot 3 deliveries per minute plus API/webhook drains are normally sufficient; large backlogs take additional ticks.

## Validation and limits

Run the full DEPLOY.md checklist. Test unauthenticated cron → 401 and authenticated cron → 200, then a scheduled reminder with Mac closed. Check Telegram getWebhookInfo for delivery errors. A successful Vercel build alone does not validate the database, webhook, or minute scheduling.

Vercel function HTTP payload limit can be smaller than the SSH API's 16 MB limit (currently 4.5 MB). Large formatted Mac notes/images may return 413. Keep these below the platform limit or choose SSH hosting; no silent attachment truncation is implemented. PHP is a community runtime: pin its version and validate upgrades in a separate deployment. Current repository CI runs the shared logic on PHP + real PostgreSQL, but does not deploy to your Vercel account without credentials.

For rollback, redeploy the preceding code revision while preserving env and DB. Use database-provider snapshots/pg_dump for backups, never `.sqlite` instructions. Changing from SQLite to PostgreSQL for an existing installation requires a separate full-data migration retaining epoch, records and delivery state; do not point a live Mac client at a fresh database and reset its guard.

Primary references (reviewed 2026-09-30): [PHP runtime](https://github.com/vercel-community/php), [Vercel runtimes](https://vercel.com/docs/functions/runtimes), [cron plan limits](https://vercel.com/docs/cron-jobs/usage-and-pricing), [cron authentication](https://vercel.com/docs/cron-jobs/manage-cron-jobs), [function limits](https://vercel.com/docs/functions/limitations), [Telegram Bot API](https://core.telegram.org/bots/api).

## Optional: Mini App only on Vercel

If the backend already runs on SSH, `python3 deploy/vercel.py --backend https://BACKEND --bot-username BOT --output .deploy/mini-vercel` prepares static assets plus a same-origin rewrite. Deploy that directory instead of this repo root. Update the SSH `mini_app_url` and bot menu intentionally. This is a separate hybrid option, not the full Vercel installation described above.
