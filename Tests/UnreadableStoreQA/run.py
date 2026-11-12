"""Regression checks from the Opus review: real loaders/actuator and extension, OS doubles."""
from pathlib import Path
import subprocess, sys, tempfile, os
repo = Path(__file__).resolve().parents[2]
here = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="tyri-opus-r1-") as d:
    d = Path(d); files = [here / "Doubles.swift", here / "main.swift"]
    for rel in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift",
                "Shared/AdHocMonitoring.swift", "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift",
                "Shared/ScheduleEnforcement.swift", "Shared/BlockResolution.swift", "Shared/BlockRule.swift", "Shared/AppGroup.swift",
                "Shared/BlockingSchedule.swift", "Shared/BlockingActuator.swift", "Shared/MonitorLedger.swift",
                "Shared/MonitorRegistration.swift", "Shared/EnforcementTransaction.swift", "Shared/SharedDefaults.swift"]:
        s = subprocess.check_output(["git", "show", os.environ["QA_REVISION"] + ":" + rel], cwd=repo, text=True) if os.environ.get("QA_REVISION") else (repo / rel).read_text()
        s = s.replace("nonisolated struct ", "struct ")
        if sys.platform == "linux": s = s.replace("import OSLog", "")
        for m in ["DeviceActivity", "FamilyControls", "ManagedSettings"]: s = s.replace("import " + m + "\n", "\n")
        s = s.replace("Date()", "QAClock.now")
        if rel.endswith("SharedDefaults.swift"):
            s = s.replace("static let suite: UserDefaults = {", "static let qaName = \"tyri-opus-r1-\\(UUID())\"\n    static let suite: UserDefaults = { return UserDefaults(suiteName: qaName)!;")
        p = d / Path(rel).name; p.write_text(s); files.append(p)
    if sys.platform == "linux": files.append(repo / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-module-cache-path", str(d / "cache"), *map(str, files), "-o", str(d / "run")], check=True)
    r = subprocess.run([str(d / "run")], env={"TYRI_TRANSACTION_PATH": str(d / "lock")}, capture_output=True, text=True)
    print(r.stdout, end=""); print(r.stderr, end="", file=sys.stderr); sys.exit(r.returncode)
