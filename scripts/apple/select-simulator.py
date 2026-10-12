#!/usr/bin/env python3
"""Select an available iPhone by UDID, without relying on a runner's model names."""
import json, subprocess
listing=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
candidates=[]
for runtime,devices in listing['devices'].items():
    if '.iOS-' not in runtime: continue
    version=tuple(int(part) for part in runtime.split('.iOS-')[1].split('-'))
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            candidates.append((version,device['name'],device['udid']))
if not candidates: raise SystemExit('No available iPhone simulator; install an iOS runtime in Xcode Settings > Components.')
print(max(candidates)[2])
