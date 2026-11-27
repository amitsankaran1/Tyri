"""Actual expiry callbacks with Apple's empty stopMonitoring argument semantics.

QA_REVISION selects old production logic while retaining corrected native doubles.
"""
from pathlib import Path
import os
import subprocess
import tempfile
import sys

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-usage-rearm-") as directory:
    temp = Path(directory)
    doubles = (repo / "Tests/CallbackQA/Doubles.swift").read_text().split("@main struct CallbackQA")[0]
    (temp / "Doubles.swift").write_text(doubles)
    files = [temp / "Doubles.swift", Path(__file__).with_name("main.swift")]
    for relative in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift",
                     "Shared/BreakMonitoring.swift", "Shared/AdHocMonitoring.swift",
                     "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift",
                     "Shared/EnforcementTransaction.swift", "Shared/MonitorLedger.swift",
                     "Shared/MonitorRegistration.swift", "Shared/VacationMode.swift"]:
        revision = os.environ.get("QA_REVISION")
        if relative == "Shared/VacationMode.swift" and revision: continue
        source = (subprocess.check_output(["git", "show", revision + ":" + relative], cwd=repo, text=True)
                  if revision else (repo / relative).read_text())
        source = source.replace("import DeviceActivity", "").replace("import FamilyControls", "")
        source = source.replace("Date()", "QAClock.now")
        if sys.platform == "linux":
            source = source.replace("import OSLog", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    if sys.platform == "linux":
        files.append(repo / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(temp / "cache"),
                    *map(str, files), "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, timeout=30)
