import json,time,shutil,textwrap,sys
from pathlib import Path
p=Path(__file__).with_name('status.json')
while True:
 try:
  s=json.loads(p.read_text());w=max(30,shutil.get_terminal_size().columns-3)
  lines=['TYRI · BLOCKING RELIABILITY QA',time.strftime('%H:%M:%S  ·  live view (refreshes every 2s)'),'',s['verdict'],'',s['phase'],'']
  for state,title,detail in s['rows']:
   lines += [f'[{state}] {title}',*textwrap.wrap(detail,width=w,initial_indent='  ',subsequent_indent='  '),'']
  lines += ['Evidence: simulator != real enforcement','Notion matrix / results:',s['notion'],'','Source: fix/blocking-reliability','New features deferred. TestFlight upload authorized after checks.']
  sys.stdout.write('\033[2J\033[H'+'\n'.join(lines)+'\n');sys.stdout.flush()
 except (OSError,json.JSONDecodeError):pass
 try:time.sleep(2)
 except KeyboardInterrupt:break
