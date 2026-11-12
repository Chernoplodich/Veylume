#!/usr/bin/env python3
"""Developer-only catalogue curation. Review generated diff before shipping.
Downloads only metadata/small model data; never imports model repository code.
"""
import concurrent.futures
import hashlib
import json
import pathlib
import urllib.request
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'Veylume/Kit/Resources/Models'
HOSTS = ['huggingface.co', 'cdn-lfs.huggingface.co', 'cdn-lfs-us-1.huggingface.co',
         'cdn-lfs-eu-1.huggingface.co', 'cas-bridge.xethub.hf.co', 'us.aws.cdn.hf.co', 'eu.aws.cdn.hf.co']
LANGS = 'bg hr cs da nl en et fi fr de el hu it lv lt mt pl pt ro ru sk sl es sv uk'.split()

def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'Veylume-catalogue-curation/1'})
    with urllib.request.urlopen(req, timeout=90) as response:
        return response.read()

def repo_info(repo):
    return json.loads(get('https://huggingface.co/api/models/' + repo + '?blobs=true'))

def artifacts(info, prefix='', local_prefix='', selected=None):
    revision = info['sha']; repo = info['id']
    siblings = [f for f in info['siblings'] if
                (f['rfilename'].startswith(prefix) and
                 (selected is None or selected(f['rfilename'][len(prefix):])))]
    def make(f):
        remote = f['rfilename']
        url = f'https://huggingface.co/{repo}/resolve/{revision}/' + urllib.parse.quote(remote)
        sha = f.get('lfs', {}).get('sha256')
        size = f.get('size')
        if not sha:
            data = get(url); sha = hashlib.sha256(data).hexdigest()
            assert size == len(data), remote
        return dict(path=local_prefix+remote[len(prefix):], url=url, bytes=size, sha256=sha)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return list(pool.map(make, siblings))

def manifest(mid, name, publisher, engine, info, files, speed, accuracy, minimum=14, memory=8, languages=LANGS, auto=True, hint=True):
    return dict(id=mid, name=name, publisher=publisher, engine=engine, revision=info['sha'], repository=info['id'],
                license=info.get('cardData', {}).get('license', 'SEE-MODEL-CARD'),
                licenseURL=f"https://huggingface.co/{info['id']}/blob/{info['sha']}/README.md",
                modelCardURL=f"https://huggingface.co/{info['id']}/tree/{info['sha']}",
                minimumOS=minimum, recommendedMemoryGB=memory, languages=languages,
                supportsAutoLanguage=auto, supportsLanguageHint=hint,
                speed=speed, accuracy=accuracy, ratingRevision=1, allowedHosts=HOSTS, artifacts=files)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    parakeet = repo_info('FluidInference/parakeet-tdt-0.6b-v3-coreml')
    components = ['Encoder.mlmodelc/', 'Decoder.mlmodelc/', 'JointDecisionv3.mlmodelc/', 'Preprocessor.mlmodelc/']
    files = artifacts(parakeet, selected=lambda p: any(p.startswith(c) for c in components) or p in ['parakeet_vocab.json', 'README.md'])
    records = [manifest('parakeet-v3', 'Parakeet TDT V3', 'NVIDIA', 'FluidAudio', parakeet, files, 5, 4)]
    whisper = repo_info('argmaxinc/whisperkit-coreml')
    for mid, variant, tokenizer, speed, accuracy, memory in [
        ('whisper-small', 'openai_whisper-small', 'openai/whisper-small', 4, 3, 8),
        ('whisper-turbo', 'openai_whisper-large-v3-v20240930_turbo', 'openai/whisper-large-v3-turbo', 4, 4, 12),
        ('whisper-large', 'openai_whisper-large-v3', 'openai/whisper-large-v3', 3, 5, 16)]:
        files = artifacts(whisper, prefix=variant+'/', selected=lambda p: '.mlmodelc/' in p or p in ['config.json', 'generation_config.json'])
        tok = repo_info(tokenizer)
        files += artifacts(tok, local_prefix='tokenizer/', selected=lambda p: p in ['tokenizer.json', 'tokenizer_config.json', 'special_tokens_map.json', 'added_tokens.json'])
        records.append(manifest(mid, {'whisper-small':'Whisper Small','whisper-turbo':'Whisper Large v3 Turbo','whisper-large':'Whisper Large v3'}[mid], 'OpenAI', 'WhisperKit', whisper, files, speed, accuracy, memory=memory, languages=LANGS+['ar','zh','ja','ko','vi','tr','hi']))
    # Current upstream documentation names additional repos that may not be
    # publicly reachable. The original conversion also hosts the v3 decoder.
    failures = []
    for repo in ['FluidInference/cohere-transcribe-q8-cache-external-coreml',
                 'FluidInference/cohere-transcribe-cache-external-coreml',
                 'FluidInference/cohere-transcribe-03-2026-coreml']:
        try:
            info = repo_info(repo)
            paths = [f['rfilename'] for f in info['siblings']]
            if any(p.startswith('q8/cohere_decoder_cache_external_v3.mlmodelc/') for p in paths):
                files = artifacts(info, prefix='q8/', selected=lambda p: p.startswith('cohere_encoder.mlmodelc/') or p.startswith('cohere_decoder_cache_external_v3.mlmodelc/'))
                files += artifacts(info, selected=lambda p: p in ['vocab.json','README.md'])
                records.append(manifest('cohere-transcribe', 'Cohere Transcribe', 'Cohere', 'FluidAudio', info, files, 5, 5, minimum=15, memory=16,
                                        languages='en de fr it es pt el nl pl vi zh ar ja ko'.split(), auto=False, hint=True))
                break
        except Exception as exc:
            failures.append({'repository': repo, 'status': getattr(exc, 'code', type(exc).__name__)})
    for record in records:
        assert record['artifacts'], record['id']
        (OUT / (record['id']+'.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n')
        print(record['id'], record['revision'], sum(f['bytes'] for f in record['artifacts']), 'bytes', len(record['artifacts']), 'files')
    (OUT / 'cohere-availability.json').write_text(json.dumps({'checked':'2026-11-10', 'failures':failures}, indent=2)+'\n')

if __name__ == '__main__':
    main()
