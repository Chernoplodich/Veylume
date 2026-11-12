#!/usr/bin/env python3
"""Developer QA only. Uses the shipped immutable manifest; never executes repo code."""
import hashlib
import json
import pathlib
import shutil
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
model_id = sys.argv[1]
assert model_id in ['parakeet-v3','cohere-transcribe','whisper-small','whisper-turbo','whisper-large']
manifest = json.loads((ROOT / f'Veylume/Kit/Resources/Models/{model_id}.json').read_text())
target = ROOT / 'artifacts/test-models' / model_id
target.mkdir(parents=True, exist_ok=True)
class Redirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, url):
        parsed = urllib.request.urlparse(url) if hasattr(urllib.request,'urlparse') else None
        from urllib.parse import urlparse
        parsed = urlparse(url)
        if parsed.scheme != 'https' or parsed.hostname not in manifest['allowedHosts']:
            raise ValueError('Untrusted model redirect')
        return super().redirect_request(request,file,code,message,headers,url)
opener = urllib.request.build_opener(Redirects())
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for data in iter(lambda:f.read(1024*1024),b''): h.update(data)
    return h.hexdigest()
for index, artifact in enumerate(manifest['artifacts']):
    relative = pathlib.PurePosixPath(artifact['path'])
    assert not relative.is_absolute() and '..' not in relative.parts
    path=target / relative
    if path.exists() and path.stat().st_size==artifact['bytes'] and digest(path)==artifact['sha256']: continue
    assert shutil.disk_usage(target).free > artifact['bytes'] + 512*1024*1024, 'Low disk'
    path.parent.mkdir(parents=True,exist_ok=True);partial=path.with_name(path.name+'.part')
    for attempt in range(3):
        try:
            with opener.open(artifact['url'],timeout=60) as response, partial.open('wb') as f:
                count=0
                while data:=response.read(1024*1024):
                    count+=len(data);assert count<=artifact['bytes'];f.write(data)
            assert count==artifact['bytes'] and digest(partial)==artifact['sha256']
            partial.replace(path);break
        except Exception:
            if attempt==2: raise
            time.sleep(1)
    print(model_id,index+1,len(manifest['artifacts']),flush=True)
print(model_id,'verified',manifest['revision'],flush=True)
