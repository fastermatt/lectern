#!/usr/bin/env python3
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("validator", ROOT / "scripts/validate-suggestion.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

class Suggestions(unittest.TestCase):
    def setUp(self):
        self.raw = (ROOT / "collaboration/fixtures/suggestion.json").read_bytes()
        self.draft = json.loads(self.raw)

    def test_multilingual_fixture_roundtrips(self):
        self.assertEqual(validator.validate(self.raw), self.draft)

    def test_rejects_invalid_fields_types_versions_and_empty_text(self):
        for key, value in [("schemaVersion", True), ("schemaVersion", 2), ("title", "  "),
                           ("details", []), ("details", "x" * 20001), ("kind", "automatic-approval"),
                           ("sourceURL", "https://user:secret@example.com"), ("sourceURL", "file:///tmp/a"),
                           ("sourceURL", "https://example.com/\nprivate"), ("language", "\ud800")]:
            with self.subTest(key=key, value_type=type(value).__name__):
                draft = dict(self.draft); draft[key] = value
                with self.assertRaises(ValueError): validator.validate(json.dumps(draft).encode())

    def test_extra_and_missing_fields_rejected(self):
        for draft in [dict(self.draft, apiKey="example"), {k:v for k,v in self.draft.items() if k != "reference"}]:
            with self.assertRaises(ValueError): validator.validate(json.dumps(draft).encode())

    def test_duplicate_and_oversized_input_rejected(self):
        with self.assertRaises(ValueError): validator.validate(b'{"kind":"translation","kind":"usability"}')
        with self.assertRaises(ValueError): validator.validate(b' ' * (validator.MAX_BYTES + 1))

if __name__ == "__main__": unittest.main()
