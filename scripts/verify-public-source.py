#!/usr/bin/env python3
"""Validate public corpus policy and snapshot integrity; Python standard library only."""
import argparse, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
RES=ROOT/'Sources/StudyTable/Resources'
MANIFEST=ROOT/'docs/resource-snapshot.json'
ALLOWED={'calvin','calvin-helloao','matthew-henry','mhcc','john-gill','keil-delitzsch','jamieson-fausset-brown','tsk'}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--write-manifest',action='store_true');args=parser.parse_args()
    registry=json.loads((RES/'Study/sources.json').read_text())['sources']
    if set(registry)-ALLOWED:raise SystemExit('Unreviewed study source in public snapshot')
    counts={key:0 for key in registry}
    for path in (RES/'Study').glob('*/*.json'):
        for entry in json.loads(path.read_text())['entries']:
            if entry['source'] not in registry:raise SystemExit('Unreviewed entry in '+str(path.relative_to(ROOT)))
            counts[entry['source']]+=1
    if any('.hcf.' in link['entryID'] for link in json.loads((RES/'Confession/wcf-links.json').read_text())['links']):raise SystemExit('Withheld source candidate preview remains')
    for edition in ['BSB','KJV','WEB']:
        if len(json.loads((RES/f'Scripture/{edition}/manifest.json').read_text())['books'])!=66:raise SystemExit('Incomplete Scripture pack')
    rights=json.loads((RES/'Reference/apostolic-fathers-rights.json').read_text())
    for path,key in [('Reference/apostolic-fathers.json','generatedJSONSHA256'),('Licenses/project-gutenberg-77576-full-license.txt','fullLicenseSHA256')]:
        if hashlib.sha256((RES/path).read_bytes()).hexdigest()!=rights[key]:raise SystemExit('Patristic source/notice integrity failure')
    paths=sorted([p for folder in [RES,ROOT/'scripture-source',ROOT/'resource-inputs'] for p in folder.rglob('*') if p.is_file() and p.name!='.DS_Store'])
    if any(p.is_symlink() for p in paths):raise SystemExit('Resource symlinks are not allowed')
    files={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    if args.write_manifest:
        MANIFEST.write_text(json.dumps({'schema':1,'files':files},indent=2,sort_keys=True)+'\n')
        print('Recorded reviewed snapshot; inspect and commit the manifest diff.')
    elif not MANIFEST.exists() or json.loads(MANIFEST.read_text())['files']!=files:
        raise SystemExit('Snapshot differs. Review changes and explicitly update the manifest.')
    print(f'Public snapshot verified: {len(files)} files, {sum(counts.values())} study entries, no HCF entries.')
if __name__=='__main__':main()
