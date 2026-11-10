from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[2]
subprocess.run(["python3", str(Path(__file__).with_name("source_guard.py"))], check=True)
with tempfile.TemporaryDirectory(prefix="tyri-foreground-recovery-") as directory:
    temp = Path(directory)
    base = (root / "Tests/CallbackQA/Doubles.swift").read_text().split("@main struct CallbackQA")[0]
    base = base.replace("static func reconcile(block: BlockRule, stopMonitoring:", "static func reconcile(block: BlockRule, now: Date = Date(), stopMonitoring:")
    base = base.replace("Self.events[name] = events", "Self.events[name] = events; try Probe.afterStart(name)")
    (temp / "Doubles.swift").write_text(base)
    files = [temp / "Doubles.swift", Path(__file__).with_name("main.swift")]
    for relative in ["Tyri/Services/ForegroundRecovery.swift", "TyriMonitor/TyriMonitorExtension.swift",
                     "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift", "Shared/AdHocMonitoring.swift",
                     "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift"]:
        source = (root / relative).read_text()
        for module in ["Combine", "DeviceActivity", "FamilyControls"]:
            source = source.replace("import " + module, "")
        source = source.replace("Date()", "QAClock.now")
        if sys.platform == "linux": source = source.replace("import OSLog", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    files.extend(root / path for path in ["Shared/MonitorLedger.swift", "Shared/MonitorRegistration.swift", "Shared/EnforcementTransaction.swift"])
    if sys.platform == "linux": files.append(root / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(temp / "cache"), *map(str, files),
                    "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, timeout=25)
