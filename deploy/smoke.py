#!/usr/bin/env python3
"""Read-only HTTP checks; never prints response bodies or credentials."""
import argparse
import json
import urllib.error
import urllib.request
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('base_url')
a=p.parse_args();base=a.base_url.rstrip('/')
if not base.startswith('https://'):p.error('Public deployments require HTTPS')
def request(path,body=None):
    req=urllib.request.Request(base+path,data=body,headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=20) as r:return r.status,r.read(),r.headers
    except urllib.error.HTTPError as e:return e.code,e.read(),e.headers
code,body,_=request('/index.php?route=health')
assert code==200 and json.loads(body).get('service')=='flodo-open','Health failed'
for route in ['sync','mini-sync']:
    code,_,_=request('/index.php?route='+route,b'{}')
    assert code==401,'Unauthenticated '+route+' must return 401'
code,body,headers=request('/mini/index.php')
assert code==200 and b'Flodo Open' in body and 'Content-Security-Policy' in headers,'Mini App failed'
for path in ['/private/config.php','/private/data/flodo.sqlite','/private/data/flodo.sqlite-wal','/private/data/flodo.sqlite-shm','/config.php','/data/flodo.sqlite','/.env','/bundle.tar.gz','/server/config.vercel.php','/server/src/core.php']:
    code,_,_=request(path)
    assert code in (403,404),'Unexpected public private path: '+path
print('PASS: HTTPS health, unauthenticated denial, Mini App CSP and private path probes')
