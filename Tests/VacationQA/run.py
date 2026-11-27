"""TSK-174 vacation mode: production schedule, usage and extension paths with OS doubles.

Uses the real models, ScheduleEnforcement, UsageMonitoring, BlockingActuator and
TyriMonitorExtension with UnreadableStoreQA's DeviceActivity/ManagedSettings doubles.
The calendar runs in UTC so fixed instants are deterministic.
"""
from pathlib import Path
import os, subprocess, sys, tempfile
repo = Path(__file__).resolve().parents[2]
here = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="tyri-vacation-qa-") as d:
    d = Path(d); files = [repo / "Tests/UnreadableStoreQA/Doubles.swift", here / "main.swift"]
    for rel in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift",
                "Shared/AdHocMonitoring.swift", "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift",
                "Shared/ScheduleEnforcement.swift", "Shared/BlockResolution.swift", "Shared/BlockRule.swift", "Shared/AppGroup.swift",
                "Shared/BlockingSchedule.swift", "Shared/BlockingActuator.swift", "Shared/MonitorLedger.swift",
                "Shared/MonitorRegistration.swift", "Shared/EnforcementTransaction.swift", "Shared/SharedDefaults.swift",
                "Shared/VacationMode.swift"]:
        s = (repo / rel).read_text()
        s = s.replace("nonisolated struct ", "struct ")
        if sys.platform == "linux": s = s.replace("import OSLog", "")
        for m in ["DeviceActivity", "FamilyControls", "ManagedSettings"]: s = s.replace("import " + m + "\n", "\n")
        s = s.replace("Date()", "QAClock.now")
        if rel.endswith("SharedDefaults.swift"):
            s = s.replace("static let suite: UserDefaults = {", "static let qaName = \"tyri-vacation-\\(UUID())\"\n    static let suite: UserDefaults = { return UserDefaults(suiteName: qaName)!;")
        p = d / Path(rel).name; p.write_text(s); files.append(p)
    if sys.platform == "linux": files.append(repo / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-module-cache-path", str(d / "cache"), *map(str, files), "-o", str(d / "run")], check=True)
    env = dict(os.environ, TZ="UTC", TYRI_TRANSACTION_PATH=str(d / "lock"))
    r = subprocess.run([str(d / "run")], env=env, capture_output=True, text=True)
    print(r.stdout, end=""); print(r.stderr, end="", file=sys.stderr)
    if r.returncode or "FAIL:" in r.stdout: sys.exit(r.returncode or 1)
