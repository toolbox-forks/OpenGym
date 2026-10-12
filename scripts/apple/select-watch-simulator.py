#!/usr/bin/env python3
import json,subprocess,re
runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','--json']))['runtimes']
watch=[r for r in runtimes if 'watchOS' in r.get('identifier','') and r.get('isAvailable',False)]
if not watch: raise SystemExit('No available watchOS simulator runtime; run xcodebuild -downloadPlatform watchOS.')
watch.sort(key=lambda r:tuple(int(v) for v in re.findall(r'\d+',r.get('version','0'))),reverse=True)
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))['devices']
for runtime in watch:
 candidates=[d for d in devices.get(runtime['identifier'],[]) if d.get('isAvailable',True) and 'Watch' in d['name']]
 candidates.sort(key=lambda d:('Ultra' in d['name'],d['name']),reverse=True)
 if candidates: print(candidates[0]['udid']);break
else: raise SystemExit('No available Apple Watch device for the installed runtime.')
