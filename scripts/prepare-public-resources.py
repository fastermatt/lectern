#!/usr/bin/env python3
"""Apply Thruline's conservative study-text release policy to a *staged* resource bundle.

Never edits the canonical resources or raw inputs. Unknown source IDs fail closed.
HCF text is withheld until an exact edition/translation has redistribution evidence.
This gate is not a blanket legal clearance of unrelated assets or future downloads.
"""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANONICAL = ROOT / 'Sources/StudyTable/Resources'
ALLOWED = {
    'calvin', 'calvin-helloao', 'matthew-henry', 'mhcc', 'john-gill',
    'keil-delitzsch', 'jamieson-fausset-brown', 'tsk',
}
WITHHELD = {'hcf'}


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def prepare(resources):
    if resources.is_symlink():
        raise ValueError('Staged resources must not contain symbolic links.')
    resources = resources.resolve()
    if resources == CANONICAL.resolve() or CANONICAL.resolve() in resources.parents:
        raise ValueError('Refusing to edit canonical resources; pass a staged bundle.')
    if not resources.is_dir() or resources.is_symlink():
        raise ValueError('Expected a staged resources directory.')
    # Reject links, which could cause a staged edit to change source files outside the stage.
    if any(p.is_symlink() for p in resources.rglob('*')):
        raise ValueError('Staged resources must not contain symbolic links.')
    study = resources / 'Study'
    registry_path = study / 'sources.json'
    registry = json.loads(registry_path.read_text())
    unknown = set(registry['sources']) - ALLOWED - WITHHELD
    if unknown:
        raise ValueError('Unreviewed source IDs: ' + ', '.join(sorted(unknown)))
    manifest = json.loads((resources / 'Scripture/BSB/manifest.json').read_text())
    chapters = {b['code']: len(b['verses']) for b in manifest['books']}
    included, excluded = Counter(), Counter()
    pending, removals = [], []
    input_digest = hashlib.sha256()
    for path in sorted(study.glob('*/*.json')):
        original = path.read_bytes()
        data = json.loads(original)
        if not isinstance(data, dict) or 'entries' not in data:
            raise ValueError('Unexpected study shard: ' + str(path.relative_to(study)))
        input_digest.update(str(path.relative_to(study)).encode())
        input_digest.update(original)
        retained = []
        for entry in data['entries']:
            source = entry['source']
            if source in WITHHELD:
                excluded[source] += 1
            elif source not in ALLOWED or source not in registry['sources']:
                raise ValueError('Unreviewed entry source: ' + source)
            else:
                retained.append(entry)
                included[source] += 1
        if data.get('code') not in chapters or not 1 <= data.get('chapter', 0) <= chapters[data['code']]:
            if retained:
                raise ValueError('Retained entries outside supported canon: ' + path.name)
            removals.append(path)
        else:
            data['entries'] = retained
            pending.append((path, encode(data)))
    links_path = resources / 'Confession/wcf-links.json'
    links = json.loads(links_path.read_text()) if links_path.exists() else None
    removed_links = []
    if links is not None:
        for link in links['links']:
            if '.hcf.' in link['entryID']:
                if link['state'] != 'candidate':
                    raise ValueError('Reviewed HCF link requires an explicit editorial migration')
                removed_links.append(link['entryID'])
        links['links'] = [link for link in links['links'] if '.hcf.' not in link['entryID']]
    # Validate all input before making any change to the stage.
    registry['sources'] = {k: v for k, v in registry['sources'].items() if k in ALLOWED}
    for path, content in pending:
        path.write_text(content, encoding='utf-8')
    for path in removals:
        path.unlink()
    registry_path.write_text(encode(registry), encoding='utf-8')
    if links is not None:
        links_path.write_text(encode(links), encoding='utf-8')
    report = {
        'withheldCandidateLinks': removed_links,
        'schema': 1, 'profile': 'public-study-text', 'policyDate': '2026-10-27',
        'includedStudyEntries': dict(sorted(included.items())),
        'withheldStudyEntries': dict(sorted(excluded.items())),
        'inputStudySHA256': input_digest.hexdigest(),
        'removedEmptyOutOfCanonShards': [str(p.relative_to(study)) for p in removals],
        'notice': 'HCF excerpts withheld pending edition-level redistribution verification. '
                  'Core Bible study needs no account, publisher key or paid AI. '
                  'Optional publisher texts remain subject to their own terms.',
    }
    (resources / 'public-resource-report.json').write_text(encode(report), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resources', type=Path)
    args = parser.parse_args()
    try:
        report = prepare(args.resources)
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(1, f'Resource gate failed: {error}\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
