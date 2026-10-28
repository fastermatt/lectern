import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('public_resources', Path(__file__).with_name('prepare-public-resources.py'))
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PublicResourceTests(unittest.TestCase):
    def fixture(self, extra=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / 'Study/GEN').mkdir(parents=True)
        (root / 'Study/DAN').mkdir(parents=True)
        (root / 'Scripture/BSB').mkdir(parents=True)
        sources = {'calvin': {'license': 'Public domain'}, 'hcf': {'license': 'Mixed'}}
        entries = [{'source': 'calvin', 'id': 'ok'}, {'source': 'hcf', 'id': 'withheld'}]
        if extra:
            entries.append({'source': extra, 'id': 'unknown'})
        (root / 'Study/sources.json').write_text(json.dumps({'sources': sources}))
        (root / 'Study/GEN/1.json').write_text(json.dumps({'code': 'GEN', 'chapter': 1, 'entries': entries}))
        (root / 'Study/DAN/13.json').write_text(json.dumps({'code': 'DAN', 'chapter': 13, 'entries': [{'source': 'hcf'}]}))
        (root / 'Scripture/BSB/manifest.json').write_text(json.dumps({'books': [{'code': 'GEN', 'verses': [31]}, {'code': 'DAN', 'verses': [1] * 12}]}))
        return root

    def test_withholds_mixed_rights_text_and_empty_noncanonical_chapters(self):
        root = self.fixture()
        report = policy.prepare(root)
        self.assertEqual(report['includedStudyEntries'], {'calvin': 1})
        self.assertEqual(report['withheldStudyEntries'], {'hcf': 2})
        self.assertEqual(json.loads((root/'Study/GEN/1.json').read_text())['entries'], [{'source': 'calvin', 'id': 'ok'}])
        self.assertNotIn('hcf', json.loads((root/'Study/sources.json').read_text())['sources'])
        self.assertFalse((root/'Study/DAN/13.json').exists())

    def test_candidate_previews_from_withheld_sources_are_removed(self):
        root = self.fixture()
        (root/'Confession').mkdir()
        path = root/'Confession/wcf-links.json'
        path.write_text(json.dumps({'links': [
            {'entryID': 'ROM.8.30-30.hcf.example', 'state': 'candidate', 'excerptPreview': 'withheld text'},
            {'entryID': 'GEN.1.1-1.calvin.example', 'state': 'candidate'}]}))
        report = policy.prepare(root)
        self.assertEqual(len(json.loads(path.read_text())['links']), 1)
        self.assertEqual(report['withheldCandidateLinks'], ['ROM.8.30-30.hcf.example'])

    def test_reviewed_withheld_link_requires_explicit_migration(self):
        root = self.fixture()
        (root/'Confession').mkdir()
        path = root/'Confession/wcf-links.json'
        path.write_text(json.dumps({'links': [{'entryID': 'ROM.8.30-30.hcf.example', 'state': 'curated'}]}))
        before = (root/'Study/GEN/1.json').read_bytes()
        with self.assertRaisesRegex(ValueError, 'explicit editorial migration'):
            policy.prepare(root)
        self.assertEqual(before, (root/'Study/GEN/1.json').read_bytes())

    def test_unknown_source_fails_without_changing_stage(self):
        root = self.fixture('unreviewed')
        before = (root/'Study/GEN/1.json').read_bytes()
        with self.assertRaisesRegex(ValueError, 'Unreviewed'):
            policy.prepare(root)
        self.assertEqual(before, (root/'Study/GEN/1.json').read_bytes())
        self.assertTrue((root/'Study/DAN/13.json').exists())

    def test_canonical_input_is_never_modified(self):
        with self.assertRaisesRegex(ValueError, 'canonical'):
            policy.prepare(policy.CANONICAL)

    def test_symlinks_fail_without_following(self):
        root = self.fixture()
        (root/'external').symlink_to(policy.CANONICAL)
        with self.assertRaisesRegex(ValueError, 'symbolic'):
            policy.prepare(root)


if __name__ == '__main__':
    unittest.main()
