"""Run production callbacks and lifecycle helpers against deterministic OS/store doubles."""
from pathlib import Path
import subprocess
import tempfile
import os
repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-callback-qa-") as directory:
    temp = Path(directory)
    files = [Path(__file__).with_name("Doubles.swift")]
    for relative in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift", "Shared/AdHocMonitoring.swift", "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift"]:
        if relative == 'Shared/EnforcementDiagnostics.swift' and os.environ.get('QA_REVISION'): continue
        if relative == 'Shared/UsageProgress.swift' and os.environ.get('QA_REVISION') == '4a39721': continue
        source = subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+relative],cwd=repo,text=True) if os.environ.get('QA_REVISION') else (repo / relative).read_text()
        source = source.replace("import DeviceActivity", "").replace("import FamilyControls", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    if not os.environ.get('QA_REVISION'): files.append(repo/'Shared/EnforcementTransaction.swift')
    subprocess.run(["swiftc", "-module-cache-path", str(temp / "cache"), *map(str, files), "-o", str(temp / "run")], check=True)
    result = subprocess.run([str(temp / "run")], capture_output=True, text=True, check=True)
    print(result.stdout, end="")
    if "FAIL:" in result.stdout: raise SystemExit(1)
