#!/usr/bin/env python3
"""Install one owned cron block without altering other jobs. Run as the web PHP user."""
import argparse
import hashlib
from pathlib import Path
import shlex
import subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--private',required=True,type=Path)
p.add_argument('--php',default='/usr/bin/php')
p.add_argument('--print-only',action='store_true')
a=p.parse_args()
root=a.private.resolve()
for value in [str(root),a.php]:
    if any(c in value for c in ['\n','\r','%']):p.error('Newlines and % are not supported in cron paths')
if not (root/'src/worker.php').is_file():p.error('Install server first')
command=' '.join([shlex.quote(a.php),shlex.quote(str(root/'src/worker.php'))])+' >> '+shlex.quote(str(root/'data/worker.log'))+' 2>&1'
if a.print_only:print('* * * * * '+command);raise SystemExit
marker='flodo-'+hashlib.sha256(str(root).encode()).hexdigest()[:12]
begin,end='# BEGIN '+marker,'# END '+marker
old=subprocess.run(['crontab','-l'],capture_output=True,text=True)
if old.returncode and 'no crontab' not in old.stderr.lower():raise SystemExit('Cannot read crontab; use --print-only and hosting scheduler')
text=old.stdout
if begin in text:
    start=text.index(begin);stop=text.index(end,start)+len(end)
    text=text[:start]+text[stop:]
text=text.rstrip()+'\n'+begin+'\n* * * * * '+command+'\n'+end+'\n'
subprocess.run(['crontab','-'],input=text,text=True,check=True)
print('Installed one cron block. Existing jobs preserved.')
