from pathlib import Path
import subprocess,tempfile,os
r=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tyri-nfc-state-') as d:
 d=Path(d);f='Tyri/Services/NFCManager.swift'
 s=subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+f],cwd=r,text=True) if os.environ.get('QA_REVISION') else (r/f).read_text()
 s=s.replace('@preconcurrency import CoreNFC','')
 (d/'NFCManager.swift').write_text(s)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(d/'cache'),str(d/'NFCManager.swift'),str(Path(__file__).with_name('main.swift')),str(r/'Shared/EnforcementTransaction.swift'),'-o',str(d/'run')],check=True)
 subprocess.run([str(d/'run')],check=True)
