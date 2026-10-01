#!/usr/bin/env python3
"""Create a private, portable deployment bundle. Does not call Telegram or SSH."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shutil
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ['index.html', 'index.php', '.htaccess', 'app.mjs', 'model.mjs', 'icons.mjs', 'gestures.mjs','images.mjs', 'style.css']

def https_url(value):
    parsed = urlparse(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('Use an absolute HTTPS URL without credentials, query or fragment')
    return value.rstrip('/')

def private_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    tmp = path.with_suffix('.tmp')
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.chmod(tmp, 0o600)
    tmp.replace(path)

def prepare(settings_path, output):
    settings = json.loads(settings_path.read_text())
    base = https_url(settings['public_url'])
    mini = https_url(settings.get('mini_app_url') or base + '/mini/index.php')
    if not re.fullmatch(r'[1-9][0-9]{3,19}', str(settings.get('owner_id', ''))):
        raise ValueError('owner_id must be the explicitly identified owner, never an arbitrary first sender')
    if not re.fullmatch(r'[A-Za-z0-9_]{5,32}', settings.get('bot_username', '')) or settings['bot_username'].startswith('YOUR_'):
        raise ValueError('Set bot_username from getMe')
    if not re.fullmatch(r'[0-9]{5,}:[A-Za-z0-9_-]{30,}', settings.get('bot_token', '')):
        raise ValueError('Invalid bot_token format')
    if settings.get('transport', 'polling') not in ('polling', 'webhook'):
        raise ValueError('transport must be polling or webhook')
    for name in ['sync_token', 'webhook_secret']:
        settings.setdefault(name, secrets.token_hex(32))
        if not re.fullmatch(r'[A-Za-z0-9_-]{43,256}', settings[name]):
            raise ValueError(name + ' must be a random 256-bit secret (hex or base64url)')
    settings['public_url'], settings['mini_app_url'] = base, mini
    # Persist generated secrets before building, so reruns never rotate credentials.
    private_json(settings_path, settings)
    if output.exists():
        raise ValueError('Output already exists; use a new bundle directory')
    output.mkdir(parents=True, mode=0o700)
    shutil.copytree(ROOT / 'server/src', output / 'private/src')
    config = {k: settings[k] for k in ['owner_id', 'bot_token', 'sync_token', 'webhook_secret', 'mini_app_url']}
    config.update(timezone=settings.get('timezone', 'Europe/Moscow'), transport=settings.get('transport', 'polling'), telegram_api_ip=settings.get('telegram_api_ip'))
    blob = base64.b64encode(json.dumps(config).encode()).decode()
    config_path = output / 'private/config.php'
    config_path.write_text("<?php\n$c=json_decode(base64_decode('" + blob + "'),true,512,JSON_THROW_ON_ERROR);\n$c['data_dir']=__DIR__.'/data';\nreturn $c;\n")
    config_path.chmod(0o600)
    mini_dir = output / 'public/mini'
    mini_dir.mkdir(parents=True)
    for asset in ASSETS:
        shutil.copy2(ROOT / 'mini-app' / asset, mini_dir / asset)
    (mini_dir / 'config.mjs').write_text('export const BOT_USERNAME=' + json.dumps(settings['bot_username']) + ";\nexport const API_URL='../index.php?route=mini-sync';\n")
    for asset in ['install.php', 'admin.php', 'cron.py']:
        shutil.copy2(ROOT / 'deploy' / asset, output / asset)
    private_json(output / 'client.json', {'endpoint': base + '/index.php?route=sync', 'token': settings['sync_token']})
    (output / 'public-url.txt').write_text(base)
    return output

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--settings', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    try:
        prepare(a.settings, a.output)
        print('Bundle created. It contains secrets: keep it outside web root and Git.')
    except (ValueError, KeyError, OSError) as e:
        p.exit(1, 'Preparation failed: ' + str(e) + '\n')

if __name__ == '__main__':
    main()
