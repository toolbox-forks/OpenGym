#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]);status=int(sys.argv[2])
def annotation(level,message):
 print('::'+level+'::'+message.replace('%','%25').replace('\r','%0D').replace('\n','%0A'))
if status:
 for name in ['watch-release.log','watch-device-build.log','watch-tests.log','watch-pair.log']:
  p=root/name
  if not p.exists():continue
  lines=p.read_text(errors='replace').splitlines();print('\n'.join(lines[-20:]))
  for index,line in enumerate(lines):
   if re.search(r'error:|XCTAssert.*failed|Test Case .*\bfailed\s*\(|Testing failed:',line,re.I):
    text='\n'.join(lines[index:index+120]) if 'XCTAssert' in line else line
    annotation('error',name+': '+text[:16000])
else:
 data=json.loads((root/'watch-test-summary.json').read_text())
 total=int(data['totalTestCount']);passed=int(data['passedTests']);failed=int(data['failedTests']);skipped=int(data['skippedTests'])
 if total<2 or passed!=total or failed or skipped:
  annotation('error',f'Watch UI gate failed: {total} total, {passed} passed, {failed} failed, {skipped} skipped.');raise SystemExit(1)
 annotation('notice',f'VERIFIED Watch simulator UI tests: {total} executed, {passed} passed, {failed} failed, {skipped} skipped.')
