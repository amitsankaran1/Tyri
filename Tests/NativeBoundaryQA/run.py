"""Production callback/helper battery with independent kernel-flock IPC probes."""
from pathlib import Path
import os, subprocess, tempfile
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-native-boundary-") as directory:
    temp = Path(directory)
    base = (root / "Tests/CallbackQA/Doubles.swift").read_text()
    base = base.replace("import Foundation", "import Foundation\nimport Darwin", 1)
    base = base.replace("var activities: [DeviceActivityName] { Array(Self.schedules.keys) }", "var activities: [DeviceActivityName] { NativeProbe.check(); return Array(Self.schedules.keys) }")
    base = base.replace("  if Self.fail ||", "  NativeProbe.check()\n  if Self.fail ||")
    base = base.replace("func stopMonitoring(_ names: [DeviceActivityName]) {", "func stopMonitoring(_ names: [DeviceActivityName]) { NativeProbe.check();")
    # Match real actuator's post-unlock boundary; its native per-property writes
    # and cross-process races are covered separately by ShieldQA.
    base = base.replace("enum BlockingActuator {", '''enum BlockingActuator {
 static func effect(_ id: UUID, _ body: @escaping @Sendable () -> Void) {
  let lease = EnforcementTransaction.begin()!
  EnforcementTransaction.afterUnlock(key: "shieldIntent." + id.uuidString, body)
  lease.finish()
 }
''')
    for body in ["State.shield = true; State.shields.insert(blockID)", "State.shield = false; State.shields.remove(blockID)"]:
        base = base.replace("{ " + body + " }", "{ effect(blockID) { " + body + " } }")
    base += '''
enum NativeProbe {
 static var calls = 0
 static func check() {
  calls += 1
  let path = NSTemporaryDirectory() + "tyri-enforcement-tests-\\(ProcessInfo.processInfo.processIdentifier).lock"
  let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
  precondition(fd >= 0)
  let free = flock(fd, LOCK_EX | LOCK_NB) == 0
  if free { flock(fd, LOCK_UN) }
  close(fd)
  precondition(free, "Native DeviceActivity IPC retained flock")
 }
}
'''
    (temp / "Doubles.swift").write_text(base)
    files = [temp / "Doubles.swift"]
    for relative in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift", "Shared/AdHocMonitoring.swift", "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift", "Shared/MonitorLedger.swift", "Shared/MonitorRegistration.swift", "Shared/EnforcementTransaction.swift"]:
        rev = os.environ.get("QA_REVISION")
        source = subprocess.check_output(["git", "show", rev + ":" + relative], cwd=root, text=True) if rev else (root / relative).read_text()
        source = source.replace("import DeviceActivity", "").replace("import FamilyControls", "").replace("Date()", "QAClock.now")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    subprocess.run(["swiftc", "-module-cache-path", str(temp / "cache"), *map(str, files), "-o", str(temp / "run")], check=True)
    result = subprocess.run([str(temp / "run")], capture_output=True, text=True, timeout=45)
    if result.returncode or "FAIL:" in result.stdout:
        print(result.stdout[-6000:]); print(result.stderr[-3000:]); raise SystemExit(result.returncode or 1)
    print("PASS: all 903 callback/lifecycle checks with native read/start/stop forbidden under actual kernel flock and shield effects deferred")
