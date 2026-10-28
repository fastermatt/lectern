#!/usr/bin/env python3
"""Validate a v1 contribution draft with Python 3's standard library, offline.
No network, subprocesses, credentials or local app stores. Never echo field contents.
"""
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit

FIELDS = {"schemaVersion", "kind", "title", "resource", "reference", "language", "details", "sourceURL"}
KINDS = {"text-correction", "resource-suggestion", "translation", "usability"}
MAX_BYTES = 262144


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate field names are not allowed.")
        result[key] = value
    return result


def validate(data):
    if len(data) > MAX_BYTES:
        raise ValueError("Draft exceeds the 256 KiB limit.")
    try:
        draft = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object)
    except (UnicodeError, json.JSONDecodeError, RecursionError):
        raise ValueError("Draft must be a valid UTF-8 JSON object.") from None
    if not isinstance(draft, dict) or set(draft) != FIELDS:
        raise ValueError("Draft has missing or unsupported fields.")
    if type(draft["schemaVersion"]) is not int or draft["schemaVersion"] != 1:
        raise ValueError("Unsupported schema version.")
    if any(not isinstance(draft[field], str) for field in FIELDS - {"schemaVersion"}):
        raise ValueError("Draft text fields must contain strings.")
    if draft["kind"] not in KINDS:
        raise ValueError("Unsupported contribution kind.")
    for key in ("title", "resource", "reference", "language", "details", "sourceURL"):
        limit = 20000 if key == "details" else 1000
        if len(draft[key]) > limit or any(0xD800 <= ord(c) <= 0xDFFF for c in draft[key]):
            raise ValueError("A text field exceeds its limit or contains invalid Unicode.")
    if not draft["title"].strip() or not draft["details"].strip():
        raise ValueError("Title and details must not be blank.")
    source = draft["sourceURL"]
    if source:
        try:
            url = urlsplit(source)
            valid = (source.startswith("https://") and url.scheme == "https" and bool(url.hostname)
                     and url.username is None and url.password is None
                     and not any(c.isspace() or ord(c) < 32 for c in source))
        except ValueError:
            valid = False
        if not valid:
            raise ValueError("Source must be an HTTPS link without embedded credentials, or empty.")
    return draft


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 scripts/validate-suggestion.py draft.json", file=sys.stderr)
        return 2
    try:
        with Path(sys.argv[1]).open("rb") as stream:
            validate(stream.read(MAX_BYTES + 1))
    except OSError:
        print("Could not read the draft file.", file=sys.stderr)
        return 1
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1
    print("Valid Lectern suggestion v1. No content was sent or changed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
