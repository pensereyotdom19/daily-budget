"""Builds DailyBudget/Localizable.xcstrings (English + Khmer).

1. Build the app once (SWIFT_EMIT_LOC_STRINGS makes Xcode list every string it finds).
2. python3 tools/make_strings.py
It reads those lists from build/DD, adds the Khmer from tools/km_translations.py, and fails if
any string has no translation, or if a translation changes the placeholders.
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from km_translations import KM, KEEP  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build/DD/Build/Intermediates.noindex")
# Strings passed into our own view initializers aren't listed by Xcode, so they are named here.
EXTRA = ["6-month plan", "Spent so far", "Savings", "Money kept aside", "SPENT TODAY", "Today", "History",
         "Summary", "Plan finished", "Plan so far", "Every month", "Recurring", "Account", "Backup & sync", "Settings", "Daily Budget"]

keys = []
for f in sorted(glob.glob(f"{BUILD}/DailyBudget.build/*/DailyBudget*.build/Objects-normal/*/*.stringsdata")):
    for items in json.load(open(f)).get("tables", {}).values():
        for item in items:
            if item["key"] not in keys:
                keys.append(item["key"])
if not keys:
    sys.exit("No extracted strings found. Build the app first.")
keys += [k for k in EXTRA if k not in keys]

placeholder = re.compile(r"%(?:\d+\$)?(?:lld|@|%)")
def kinds(s):
    return sorted(re.sub(r"\d+\$", "", p) for p in placeholder.findall(s))

missing, bad = [], []
strings = {}
for k in sorted(keys):
    if k in KEEP:
        strings[k] = {"shouldTranslate": False} if k else {}
        continue
    km = KM.get(k)
    if km is None:
        missing.append(k)
        continue
    if kinds(km) != kinds(k) and not k.startswith("%lld day%@"):
        bad.append((k, km))
    strings[k] = {"localizations": {"km": {"stringUnit": {"state": "translated", "value": km}}}}

if missing or bad:
    for k in missing:
        print("missing:", repr(k))
    for k, v in bad:
        print("placeholders differ:", repr(k), "->", repr(v))
    sys.exit(1)

catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
with open(os.path.join(ROOT, "DailyBudget/Localizable.xcstrings"), "w") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
unused = sorted(set(KM) - set(keys))
print(f"{len(strings)} strings, {len(KM) - len(unused)} translated to Khmer.", f"Unused: {unused}" if unused else "")
