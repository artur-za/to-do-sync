# Instructions for an AI deploying or maintaining this repository

Read README.md and DEPLOY.md before acting. Use docs/SSH.md or docs/VERCEL.md for the selected host. The user may provide only this repository URL and hosting/bot credentials; perform the normal setup work autonomously rather than asking them to execute a long checklist.

## Discover, do not guess

- Inspect the existing deployment, PHP versions/extensions, document root, scheduler and domains before changing them. On Vercel inspect project, environment scopes, database integrations and plan limits.
- Verify the bot via getMe without printing its token. A bot token does NOT reveal the owner's Telegram user ID. Ask for the numeric ID or ask the user to send a unique pairing phrase and explicitly match that user's update. Never bind the first arbitrary sender. A user must open/start the bot before it can send them messages.
- If only Vercel credentials are given, try the existing PostgreSQL integration or provision a dedicated database through the authorized account. Do not invent DATABASE_URL. Ask only if access, owner identification, domain choice or billing approval is missing.
- Select one production URL, one database and one active Telegram transport. Do not run two pollers for the same bot. Never point previews at the production bot/database.

## Credentials and deployment

- Store local setup files under ignored .deploy/ (directory 700, secret files 600); use environment variables or stdin for tokens. Never put credentials in CLI arguments, Git, screenshots, reports or browser code. Never log Telegram API URLs containing the bot token.
- Secrets: BOT_TOKEN, DATABASE_URL, SYNC_TOKEN, WEBHOOK_SECRET, CRON_SECRET. BOT_USERNAME, PUBLIC_URL and the Mini App API URL are public.
- Generate independent random 256-bit sync/webhook/cron secrets once and preserve them on updates. Do not disable owner checks, TLS validation, initData validation or webhook/cron authentication to make deployment work.
- SSH: private config/database/backups must be outside ALL HTTP document roots. If hosting open_basedir prevents that, configure a safe separate private location or use Vercel/VPS; do not silently put secrets in public_html.
- Vercel: deploy this repo root using vercel.json, external PostgreSQL and webhook. Set all required environment values in Production. Cron must actually run every minute. Hobby's daily-only built-in cron does not meet this requirement: use an authorized external scheduler or agreed Pro plan.
- The public route health check does not verify the DB or scheduler. Check authenticated sync, bot status, cron and an end-to-end temporary task before claiming success.
- BotFather Main Mini App setup is a user-owned Telegram account action, separate from setChatMenuButton. Complete Bot API configuration automatically; if BotFather access is unavailable, give the exact bot and URL for that one remaining step.

## Preserve data

- Never replace/delete an existing database or reset epoch to fix a deployment error. Back up SQLite with backup API/VACUUM INTO, PostgreSQL with provider snapshots/pg_dump.
- Update code while keeping config and data. The SSH installer preserves them and keeps old release directories. Avoid permanent deletion of unrelated files/processes/cron jobs.
- Mac app is persistent; do not force quit it while an editor may hold unsaved content. Build/sign first; request safe restart if needed.
- Use scripts/build.sh for Mac releases. It preserves a stable Apple signing identity when available; changing ad-hoc signatures can invalidate Keychain access. Never commit certificates/private keys. Background Keychain access must not show system dialogs.

## Validation and completion

- Run relevant tests, including PostgreSQL CI for database changes. Use isolated test databases; TEST_DATABASE_URL is destructive test-only input, never production.
- Run scripts/check-secrets.py and inspect git diff before push.
- Report actual verification separately from prepared-but-not-deployed paths. Give production URL, bot username, Mac endpoint, private location of saved connection credentials, scheduler status and remaining user actions. Never reproduce secrets in the completion report.
- No need to refactor the UI while deploying. Preserve task UUIDs, field merge, rich-note behavior, column defaults, stable Telegram numbering and owner-only access.
