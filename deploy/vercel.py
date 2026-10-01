#!/usr/bin/env python3
"""Prepare a static Vercel Mini App with a same-origin proxy to an existing PHP API."""
import argparse
import json
from pathlib import Path
import re
import shutil
from prepare import ROOT, https_url
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--backend',required=True,help='HTTPS base URL, without /index.php')
p.add_argument('--bot-username',required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();backend=https_url(a.backend)
if not re.fullmatch(r'[A-Za-z0-9_]{5,32}',a.bot_username):p.error('Invalid bot username')
if a.output.exists():p.error('Use a new output directory')
a.output.mkdir(parents=True)
for file in ['index.html','app.mjs','model.mjs','gestures.mjs','images.mjs','icons.mjs','style.css']:
    shutil.copy2(ROOT/'mini-app'/file,a.output/file)
(a.output/'config.mjs').write_text('export const BOT_USERNAME='+json.dumps(a.bot_username)+";\nexport const API_URL='/api/sync';\n")
config={'$schema':'https://openapi.vercel.sh/vercel.json','framework':None,'buildCommand':None,'outputDirectory':'.','rewrites':[{'source':'/api/sync','destination':backend+'/index.php?route=mini-sync'}],'headers':[{'source':'/(.*)','headers':[{'key':'Cache-Control','value':'no-store'},{'key':'Referrer-Policy','value':'no-referrer'},{'key':'X-Content-Type-Options','value':'nosniff'},{'key':'Content-Security-Policy','value':"default-src 'self'; script-src 'self' https://telegram.org; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; base-uri 'none'; form-action 'none'"}]}]}
(a.output/'vercel.json').write_text(json.dumps(config,indent=2))
print('Static Mini App prepared. Backend and reminder worker remain on the PHP host.')
