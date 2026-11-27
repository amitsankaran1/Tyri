"""Replay actual production callbacks with deterministic clock/native boundaries."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-callback-lifecycle-") as directory:
    temp = Path(directory)
    doubles = (root / "Tests/CallbackQA/Doubles.swift").read_text().split("@main struct CallbackQA")[0]
    (temp / "Doubles.swift").write_text(doubles)
    files = [temp / "Doubles.swift", Path(__file__).with_name("main.swift")]
    for relative in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift",
                     "Shared/BreakMonitoring.swift", "Shared/AdHocMonitoring.swift",
                     "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift",
                     "Shared/EnforcementTransaction.swift", "Shared/MonitorLedger.swift",
                     "Shared/MonitorRegistration.swift", "Shared/VacationMode.swift"]:
        source = (root / relative).read_text()
        for module in ["DeviceActivity", "FamilyControls"]:
            source = source.replace("import " + module, "")
        source = source.replace("Date()", "QAClock.now")
        source = source.replace("nonisolated struct ", "struct ")
        if sys.platform == "linux":
            source = source.replace("import OSLog", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    if sys.platform == "linux":
        files.append(root / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(temp / "cache"), *map(str, files),
                    "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, timeout=120)
