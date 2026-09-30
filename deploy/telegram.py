#!/usr/bin/env python3
"""Inspect/configure your bot without exposing its token in argv or logs."""
import argparse
import json
from pathlib import Path
import urllib.request
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--settings',type=Path,required=True)
p.add_argument('--configure',action='store_true')
p.add_argument('--vercel',action='store_true')
p.add_argument('--replace-webhook',action='store_true')
a=p.parse_args();s=json.loads(a.settings.read_text())
def api(method,body=None):
    request=urllib.request.Request('https://api.telegram.org/bot'+s['bot_token']+'/'+method,data=json.dumps(body or {}).encode(),headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(request,timeout=25) as r:result=json.load(r)
    except Exception:raise SystemExit('Telegram '+method+' failed (network/HTTP error; details suppressed to protect token)')
    if not result.get('ok'):raise SystemExit('Telegram '+method+' rejected request')
    return result['result']
me=api('getMe');current=api('getWebhookInfo')
print('Bot: @'+me['username'])
print('Main Mini App:',bool(me.get('has_main_web_app')))
if not a.configure:raise SystemExit
if str(s.get('owner_id','')).isdigit() is False:raise SystemExit('Set explicit numeric owner_id first')
base=s['public_url'].rstrip('/')
if not base.startswith('https://'):raise SystemExit('HTTPS required')
mini=base+'/mini/' if a.vercel else s.get('mini_app_url',base+'/mini/index.php')
webhook=base+('/api/index.php' if a.vercel else '/index.php')+'?route=webhook'
if current.get('url') and current['url']!=webhook and not a.replace_webhook:raise SystemExit('Another webhook exists. Stop the old deployment before --replace-webhook.')
if a.vercel or s.get('transport')=='webhook':
    if len(s.get('webhook_secret',''))<43:raise SystemExit('Generate webhook_secret first')
    api('setWebhook',{'url':webhook,'secret_token':s['webhook_secret'],'drop_pending_updates':False,'allowed_updates':['message','callback_query']})
else:api('deleteWebhook',{'drop_pending_updates':False})
api('setMyCommands',{'commands':[{'command':'today','description':'Задачи на сегодня'},{'command':'app','description':'Открыть задачи'}]})
menu={'type':'web_app','text':'Открыть','web_app':{'url':mini}}
api('setChatMenuButton',{'menu_button':menu})
api('setChatMenuButton',{'chat_id':s['owner_id'],'menu_button':menu})
print('Webhook/polling and menu configured. Main Mini App: configure separately in BotFather.')
