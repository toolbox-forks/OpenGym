#!/usr/bin/env python3
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(errors='replace')
status=int(sys.argv[2])
def annotation(level,message):
 print('::'+level+'::'+message.replace('%','%25').replace('\n','%0A').replace('\r','%0D'))
if status:
 print('\n'.join(text.splitlines()[-40:]))
 for line in text.splitlines():
  if 'error:' in line or 'failed' in line.lower(): annotation('error',line[:2000])
else:
 counts=re.findall(r'Executed (\d+) tests?, with (\d+) failures?',text)
 if not counts or int(counts[-1][0])<39 or int(counts[-1][1]):
  annotation('error','OpenGymKit must execute at least 39 tests with zero failures.');raise SystemExit(1)
 annotation('notice',f'VERIFIED OpenGymKit: {counts[-1][0]} tests executed, {counts[-1][1]} failures.')
