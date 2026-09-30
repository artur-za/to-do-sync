# Full deployment: SSH + PHP + SQLite

## Prerequisites

- PHP 8.2+ web/CLI, extensions `curl`, `mbstring`, `pdo_sqlite`.
- HTTPS virtual host, outbound HTTPS to api.telegram.org, cron every minute.
- SSH/scp, Python 3 locally; Python 3 remotely for automatic crontab install (or host panel scheduler).
- Web PHP and cron use the same unprivileged user; private folders 700, files 600.

Inspect host paths before running. Example values below are placeholders, not commands for an existing installation. `PRIVATE` must be outside **all** virtual-host document roots. `public_html/todo` and `public_html/private` is NOT safe even though those directories are siblings. If PHP open_basedir excludes the private path, update the hosting configuration; do not solve it by publishing credentials under web root.

## 1. Prepare local config

```sh
umask 077
mkdir -p .deploy
cp deploy/settings.example.json .deploy/settings.json
```

Fill `public_url`, `mini_app_url`, bot token, verified owner ID and `bot_username`. The username can be read with `python3 deploy/telegram.py --settings .deploy/settings.json` once the token is set. Store SSH credentials in SSH agent/config, not in this JSON or Git. Authenticate SSH normally; do not disable host key verification.

```sh
python3 deploy/prepare.py --settings .deploy/settings.json --output .deploy/bundle-001
```

This generates and persists random `sync_token` and `webhook_secret` if absent. Reusing settings preserves them. The bundle contains secrets: upload it into a private directory outside web root, never under the website or Git.

## 2. Install

Example, after replacing paths with inspected values:

```sh
ssh MY_HOST 'umask 077; mkdir -p /home/MY_USER/deploy-incoming'
scp -r .deploy/bundle-001 MY_HOST:/home/MY_USER/deploy-incoming/
ssh MY_HOST 'php /home/MY_USER/deploy-incoming/bundle-001/install.php /home/MY_USER/public_html/todo /home/MY_USER/flodo-private'
python3 deploy/smoke.py https://todo.example.com
```

If public_url includes `/todo`, use it consistently. `php` may need a versioned absolute path. The installer creates a release, switches `private/src` atomically, generates the public PHP entrypoint, initializes SQLite, preserves existing config/data, and backs up an existing DB. It refuses an existing owner/bot mismatch or unmanaged `src` directory. Do not delete the old directory to bypass that refusal: back up and plan a migration to the new layout.

Result:

```text
/home/MY_USER/flodo-private/
  config.php             secrets, 600
  data/flodo.sqlite      persistent SQLite + WAL/SHM, 600
  releases/<id>/src/     backend code
  releases/<id>/config.php -> ../../config.php
  src -> releases/<id>/src
  backups/               consistent DB snapshots
  admin.php, cron.py
/home/MY_USER/public_html/todo/
  index.php              only a require to the private backend
  mini/                  public HTML/CSS/JS, no credentials
```

Nginx must route only existing public PHP files to PHP-FPM, preserve `Authorization`, and have autoindex off. Apache needs AllowOverride for included headers/MIME rules. `.mjs` must be JavaScript MIME. The supplied Mini index.php sets CSP; do not serve `server/` as web root. On a bare VPS, provision HTTPS/PHP-FPM with these constraints before installation; the script intentionally does not overwrite existing virtual hosts.

## 3. Configure bot and scheduler

```sh
ssh MY_HOST 'php /home/MY_USER/flodo-private/admin.php setup-bot https://todo.example.com'
ssh MY_HOST 'python3 /home/MY_USER/flodo-private/cron.py --private /home/MY_USER/flodo-private --php /usr/bin/php'
ssh MY_HOST 'php /home/MY_USER/flodo-private/admin.php status'
```

Stop an old poller before starting this one. `setup-bot` refuses to replace a different existing webhook unless explicitly called with `--replace-webhook`. Polling is default. Worker runs up to 55 seconds, stores its offset only after committing an update, and uses a process lock to avoid overlap.

If crontab is controlled by the hosting panel, use `cron.py --print-only`, then create exactly that every-minute job in the panel. Do not leave both panel and crontab jobs enabled. For webhook mode set `transport=webhook` in the private config, run setup-bot again, and KEEP the worker cron for reminders/daily digest.

If the host cannot reach Telegram, first diagnose outbound network access. `telegram_api_ip` is an optional verified official API IP override with domain/TLS verification intact; do not copy somebody else's old IP or disable TLS.

## 4. Connect Mac, verify, update

For a first installation the ignored bundle's `client.json` has the endpoint and sync token. For updates the remote config is authoritative; retrieve the client config directly into a private local file without displaying it:

```sh
umask 077
ssh MY_HOST 'php /home/MY_USER/flodo-private/admin.php client-config "https://todo.example.com/index.php?route=sync"' > .deploy/client.json
```

Follow [MAC.md](MAC.md) and the acceptance checklist in [DEPLOY.md](../DEPLOY.md). Health alone is not completion. Keep logs/backups private and apply an appropriate retention policy.

Update by preparing a new bundle with the SAME settings, uploading it and rerunning install.php. Existing config is retained, not regenerated. Change configuration intentionally on the server before deployment when necessary. Old `releases/` directories are available for code rollback; point `src` to the previous release atomically. Restore DB only when needed and with writers stopped. Do not restore SQLite on top of an active WAL.
