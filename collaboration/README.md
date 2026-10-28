# A first contribution without a Mac

You can suggest a resource, correct a reference, review wording or describe a
usability problem without building Lectern or buying an AI account.

The app's **Library → Help improve Lectern** prepares a local JSON draft.
You can also copy `fixtures/suggestion.json` and edit it in a text editor.
It is an illustrative example, not an approved translation or corpus record.
Keep the field names and `schemaVersion`; write the values in your own language.
Only `title` and `details` require text. Leave other text fields blank if unknown.
Choose `text-correction`, `resource-suggestion`, `translation` or `usability`.

From the project root, with Python 3 installed on Windows, Linux or macOS:

```sh
python3 scripts/validate-suggestion.py collaboration/fixtures/suggestion.json
python3 scripts/test-suggestions.py
```

On Windows, `py -3` can replace `python3`. These commands use only the standard
library and do not contact the network. The same fixture is decoded by Swift tests.
The standalone schema is `suggestion.schema.json`; the validator also checks
nonblank fields, Unicode and HTTPS links without embedded credentials.
This validates contribution drafts, not corpus licenses, factual accuracy,
Scripture mappings or an entire resource pack.

Review your exported file before sharing it. Include source links, not whole
copyrighted works, private notes or credentials. The app adds no account, device
or study-store data. Nothing is submitted automatically. Submit a reviewed draft through an issue at
https://github.com/fastermatt/lectern/issues or ask in Discussions. Use the Security
tab for private vulnerability reports. A live repository does not imply a staffed
editorial review service.

Maintainers should credit research, testing and translation alongside code.
A draft is a suggestion; source corrections still require human review. AI
output is not evidence of historical accuracy or permission to redistribute.
