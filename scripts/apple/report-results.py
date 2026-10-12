#!/usr/bin/env python3
"""Publish concise native failures/counts as normal Actions annotations and retain full logs."""
from pathlib import Path
import json
import re
import sys

results = Path(sys.argv[1])
exit_code = int(sys.argv[2])

def annotation(level, text):
    text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::{level}::{text}')

if exit_code:
    found = []
    for name in ['iphone-release.log', 'iphone-tests.log']:
        path = results / name
        if not path.exists():
            continue
        lines = path.read_text(errors='replace').splitlines()
        print(f'Last lines of {name}:')
        print('\n'.join(lines[-30:]))
        for line in lines:
            if re.search(r'error:|XCTAssert.*failed|Test Case .*failed|Testing failed:', line, re.I):
                found.append(f'{name}: {line[:2000]}')
    for failure in found[-12:]:
        annotation('error', failure)
    if not found:
        annotation('error', f'Native command failed with exit {exit_code}; inspect retained xcresult/logs.')
else:
    summary = json.loads((results / 'iphone-test-summary.json').read_text())
    total = int(summary['totalTestCount'])
    passed = int(summary['passedTests'])
    failed = int(summary['failedTests'])
    skipped = int(summary['skippedTests'])
    if total < 14 or passed != total or failed or skipped:
        annotation('error', f'Native test gate failed: {total} total, {passed} passed, {failed} failed, {skipped} skipped; require at least 14 executed passing tests.')
        raise SystemExit(1)
    annotation('notice', f'VERIFIED OpenGym native/simulator tests: {total} executed, {passed} passed, {failed} failed, {skipped} skipped.')
