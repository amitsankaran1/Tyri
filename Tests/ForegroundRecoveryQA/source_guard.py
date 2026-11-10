"""Guard the actual first-scene entry points, in addition to the Swift IPC probe."""
from pathlib import Path
import os
import subprocess

root = Path(__file__).resolve().parents[2]
def read(path):
    if os.environ.get("QA_REVISION"):
        return subprocess.check_output(["git", "show", os.environ["QA_REVISION"] + ":" + path], cwd=root, text=True)
    return (root / path).read_text()

app = read("Tyri/TyriApp.swift")
home = read("Tyri/Views/HomeView.swift")
status = read("Tyri/Views/BlockStatusView.swift")
for call in ["reapplyAllSchedules()", "reapplyAllUsageLimits()", "reconcileExpiredLocks()", "restoreActiveBreaksIfAny()"]:
    assert call not in app, f"Synchronous launch maintenance returned: {call}"
refresh = home[home.index("    private func refresh() {"):]
for call in ["repairMissingSchedules()", "reapplyAllUsageLimits()", "reconcileExpiredLocks()", "restoreActiveBreaksIfAny()"]:
    assert call not in refresh, f"Synchronous foreground maintenance returned: {call}"
assert "UsageMonitoring.isUsageMonitorActive" not in status, "Rendering must not make a synchronous IPC read"
assert "ForegroundRecovery.shared.start()" in app
assert "ForegroundRecovery.shared.request()" in refresh
print("PASS: first-scene entry points and status rendering do not call synchronous monitoring")
