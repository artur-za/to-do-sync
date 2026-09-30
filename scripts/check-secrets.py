#!/usr/bin/env python3
"""Conservative pre-push scan. Prints paths/rule names, never matched secrets."""
import re
import subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
files=subprocess.check_output(['git','ls-files','-z','--cached','--others','--exclude-standard'],cwd=root).decode().split('\0')
rules={
    'Telegram token':r'(?<![A-Za-z0-9])[0-9]{7,}:[A-Za-z0-9_-]{30,}',
    'GitHub token':r'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}',
    'Private key':r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
}
failed=[]
for name in set(filter(None,files)):
    path=root/name
    if not path.is_file():continue
    if any(part in name.split('/') for part in ['.deploy','data','backups','.vercel']) or re.search(r'\.(?:sqlite|db|p12|pem|key)(?:-|$)',name):
        failed.append((name,'private artifact'));continue
    try:text=path.read_text()
    except UnicodeDecodeError:continue
    for rule,pattern in rules.items():
        if re.search(pattern,text):failed.append((name,rule))
if failed:
    for name,rule in failed:print('BLOCK:',name,rule)
    raise SystemExit(1)
print('PASS: no credential patterns or private artifacts in publishable files')
