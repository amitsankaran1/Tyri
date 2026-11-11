"""Production lifecycle regressions; deterministic OS/store failures and interleavings."""
from pathlib import Path
import os, subprocess, tempfile, sys
r=Path(__file__).resolve().parents[2]
def source(f):
    return subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+f],cwd=r,text=True) if os.environ.get('QA_REVISION') else (r/f).read_text()
with tempfile.TemporaryDirectory(prefix='tyri-state-qa-') as d:
    d=Path(d)
    base=(r/'Tests/CallbackQA/Doubles.swift').read_text().split('@main struct CallbackQA')[0]
    base=base.replace('static var starts = 0','static var starts = 0\n static var onStart: (() -> Void)?\n static var onStop: (() -> Void)?')
    base=base.replace('Self.events[name] = events','Self.events[name] = events\n  let callback = Self.onStart; Self.onStart = nil; callback?()')
    base=base.replace('for n in names { Self.schedules[n] = nil }','for n in names { Self.schedules[n] = nil }; let callback = Self.onStop; Self.onStop = nil; callback?()')
    (d/'Doubles.swift').write_text(base)
    files=[d/'Doubles.swift',r/'Tests/StateMachineQA/main.swift']
    for f in ['Shared/UsageMonitoring.swift','Shared/BreakMonitoring.swift','Shared/AdHocMonitoring.swift','Shared/UsageProgress.swift','Shared/EnforcementDiagnostics.swift']:
        p=d/Path(f).name;p.write_text(source(f).replace('import DeviceActivity','').replace('import FamilyControls',''));files.append(p)
    if (r/'Shared/EnforcementTransaction.swift').exists():
        files.append(r/'Shared/EnforcementTransaction.swift')
        files.extend(r / path for path in ['Shared/MonitorLedger.swift', 'Shared/MonitorRegistration.swift'])
        # Test defaults are isolated; transaction synchronizes this same suite.
    if sys.platform == 'linux':
        for path in files:
            if path.parent == d:
                path.write_text(path.read_text().replace('import OSLog', ''))
        files.append(r / 'Tests/Support/OSLog.swift')
    subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(d/'cache'),*map(str,files),'-o',str(d/'run')],check=True)
    result=subprocess.run([str(d/'run')],capture_output=True,text=True)
    print(result.stdout,end='');print(result.stderr,end='')
    raise SystemExit(result.returncode)
