#!/usr/bin/env python3
"""Write private Vercel env JSON, preserving generated credentials across reruns."""
import argparse
import json
from pathlib import Path
import secrets
from prepare import private_json, https_url
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--settings',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();s=json.loads(a.settings.read_text())
for key in ['sync_token','webhook_secret','cron_secret']:s.setdefault(key,secrets.token_hex(32))
if not s.get('database_url','').startswith(('postgres://','postgresql://')):p.error('Set database_url to your dedicated PostgreSQL connection URL with TLS')
public=https_url(s['public_url'])
env={'DATABASE_URL':s['database_url'],'BOT_TOKEN':s['bot_token'],'BOT_USERNAME':s['bot_username'],'OWNER_ID':str(s['owner_id']),'PUBLIC_URL':public,'SYNC_TOKEN':s['sync_token'],'WEBHOOK_SECRET':s['webhook_secret'],'CRON_SECRET':s['cron_secret'],'TIMEZONE':s.get('timezone','Europe/Moscow')}
private_json(a.settings,s);private_json(a.output,env)
print('Private env JSON written. Upload values using stdin; never commit this file.')
