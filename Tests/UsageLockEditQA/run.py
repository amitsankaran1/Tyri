"""Prove a lock-duration-only edit does not remint today's usage allowance.

Compiles the production Save reconciliation path (ForegroundRecovery and
UsageMonitoring) against the shared DeviceActivity double. The double's
activity identity is the stand-in for iOS's threshold counter: a new
startMonitoring call with includesPastActivity false is what drops usage
already counted today.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-usage-lock-edit-") as directory:
    temp = Path(directory)
    base = (root / "Tests/CallbackQA/Doubles.swift").read_text().split("@main struct CallbackQA")[0]
    base = base.replace("static func reconcile(block: BlockRule, stopMonitoring:", "static func reconcile(block: BlockRule, now: Date = Date(), stopMonitoring:")
    base = base.replace(
        "enum BlockingActuator {",
        "enum BlockingActuator { static var persistedOwnerIDs: Set<UUID> { Set(BlockResolution.blocks.keys) }; "
        "static var pendingClear: UUID?; static var pending: UUID?; "
        "static func replayPending() { if let id = pendingClear { State.shields.remove(id); pendingClear = nil }; "
        "if let id = pending { State.shields.insert(id) } }; static func setEffectsEnabled(_ active: Bool) {}")
    base = base.replace("Self.events[name] = events", "Self.events[name] = events; try Probe.afterStart(name)")
    (temp / "Doubles.swift").write_text(base)
    files = [temp / "Doubles.swift", Path(__file__).with_name("main.swift")]
    for relative in ["Tyri/Services/ForegroundRecovery.swift", "TyriMonitor/TyriMonitorExtension.swift",
                     "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift", "Shared/AdHocMonitoring.swift",
                     "Shared/UsageProgress.swift", "Shared/EnforcementDiagnostics.swift"]:
        source = (root / relative).read_text()
        for module in ["Combine", "DeviceActivity", "FamilyControls", "UIKit"]:
            source = source.replace("import " + module, "")
        source = source.replace("#if canImport(UIKit)", "#if TYRI_QA_UIKIT")
        source = source.replace("Date()", "QAClock.now")
        if relative == "Tyri/Services/ForegroundRecovery.swift":
            source = source.replace("nonisolated private struct RecoveryJob", "private struct RecoveryJob")
            source = source.replace(
                "return Set(DeviceActivityCenter().activities.map(\\.rawValue))",
                "return Probe.afterObserve(Set(DeviceActivityCenter().activities.map(\\.rawValue)))")
        if sys.platform == "linux":
            source = source.replace("import OSLog", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    for relative in ["Shared/MonitorLedger.swift", "Shared/MonitorRegistration.swift", "Shared/EnforcementTransaction.swift"]:
        source = (root / relative).read_text()
        source = source.replace("nonisolated struct ", "struct ")
        if relative == "Shared/EnforcementTransaction.swift":
            source = source.replace(
                "static func begin(wait: Bool = true) -> Lease? {",
                "static func begin(wait: Bool = true) -> Lease? { Probe.didBeginLease()")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    if sys.platform == "linux":
        files.append(root / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-D", "TYRI_QA_UIKIT", "-parse-as-library", "-module-cache-path", str(temp / "cache"),
                    *map(str, files), "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, timeout=25)
