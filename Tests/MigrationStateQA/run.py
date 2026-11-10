from pathlib import Path
import subprocess,tempfile,os
r=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tyri-migration-state-') as d:
 d=Path(d);files=[Path(__file__).with_name('main.swift'),r/'Shared/EnforcementTransaction.swift']
 for f in ['Tyri/Services/Migration.swift','Shared/BlockRule.swift','Shared/AppGroup.swift','Shared/BlockingSchedule.swift']:
  s=subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+f],cwd=r,text=True) if os.environ.get('QA_REVISION') else (r/f).read_text()
  for i in ['FamilyControls','ManagedSettings','DeviceActivity']:s=s.replace('import '+i,'')
  p=d/Path(f).name;p.write_text(s);files.append(p)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(d/'cache'),*map(str,files),'-o',str(d/'run')],check=True)
 subprocess.run([str(d/'run')],check=True)
