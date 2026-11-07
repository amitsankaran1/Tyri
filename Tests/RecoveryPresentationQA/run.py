from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='tyri-recovery-status-') as d:
 d=Path(d);p=d/'Status.swift';p.write_text((r/'Tyri/Views/BlockStatusView.swift').read_text().replace('import FamilyControls',''))
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(d/'cache'),str(p),str(Path(__file__).with_name('main.swift')),'-o',str(d/'run')],check=True)
 subprocess.run([str(d/'run')],check=True)
