# Server

Shared PHP 8.2+ logic: `core.php` data/sync/outbox, `bot.php` messages/scheduling, `mini-auth.php` initData validation, `database.php` SQLite/PostgreSQL adapters, `http.php` routes, `worker.php` CLI polling and reminders.

Start at [DEPLOY.md](../DEPLOY.md). [SSH guide](../docs/SSH.md) and [full Vercel guide](../docs/VERCEL.md) contain complete setup instructions. `config.example.php` is a template; a real config is never tracked. Vercel uses `config.vercel.php` to read environment variables.

SQLite transactions use BEGIN IMMEDIATE; PostgreSQL uses transaction advisory locks to serialize board mutations and revision increments. Outbox delivery is serialized independently. Telegram updates and reminder/daily queue entries are durable and deduplicated. A network failure after sendMessage success may still produce a duplicate on retry; Telegram has no idempotency key for this API.

Tests use isolated SQLite by default. CI also runs them against a dedicated disposable PostgreSQL. Never set `TEST_DATABASE_URL` to production. Database TLS is required outside the explicit CI test mode.

```sh
php server/tests/run.php
php server/tests/mini-auth.php
```

Web routes: GET health; POST sync with Bearer; POST mini-sync with X-Telegram-Init-Data; POST webhook with X-Telegram-Bot-Api-Secret-Token. Unauthorized requests return 401. Public health is a liveness check only; authenticated sync checks persistent storage. Errors do not echo tokens or task contents.
