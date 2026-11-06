from pathlib import Path
import subprocess,tempfile,os
repo=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tyri-shield-qa-') as d:
 d=Path(d);files=[Path(__file__).with_name('Doubles.swift')]
 for relative in ['Shared/BlockingActuator.swift', 'Shared/EnforcementDiagnostics.swift']:
  if relative == 'Shared/EnforcementDiagnostics.swift' and os.environ.get('QA_REVISION'): continue
  s=subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+relative],cwd=repo,text=True) if os.environ.get('QA_REVISION') else (repo/relative).read_text()
  s=s.replace('import ManagedSettings','').replace('import FamilyControls','')
  p=d/Path(relative).name;p.write_text(s);files.append(p)
 subprocess.run(['swiftc','-module-cache-path',str(d/'cache'),*map(str,files),'-o',str(d/'run')],check=True)
 subprocess.run([str(d/'run')],check=True)
