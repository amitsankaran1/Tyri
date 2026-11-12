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
    base = base.replace("enum BlockingActuator {", "enum BlockingActuator { static var persistedOwnerIDs: Set<UUID> { Set(BlockResolution.blocks.keys) }; static var pending: UUID?; static func replayPending() { if let id = pending { State.shields.insert(id) } }; static func setEffectsEnabled(_ active: Bool) {}")
    base = base.replace("static func reconcile(block: BlockRule, now: Date = Date(), stopMonitoring: Bool = true) {}", "static func reconcile(block: BlockRule, now: Date = Date(), stopMonitoring: Bool = true) { if Probe.outsideSchedule { BlockingActuator.pending = nil; State.shields.remove(block.id) } }")
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
            # `nonisolated` on a file-private value type is accepted by the
            # project compiler but not Swift 6.0 used in this Linux harness.
            source = source.replace("nonisolated private struct RecoveryJob", "private struct RecoveryJob")
            source = source.replace(
                "return Set(DeviceActivityCenter().activities.map(\\.rawValue))",
                "return Probe.afterObserve(Set(DeviceActivityCenter().activities.map(\\.rawValue)))")
        if sys.platform == "linux": source = source.replace("import OSLog", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    for relative in ["Shared/MonitorLedger.swift", "Shared/MonitorRegistration.swift", "Shared/EnforcementTransaction.swift"]:
        source = (root / relative).read_text()
        # The production compiler accepts these Swift 6.1 declarations; Swift
        # 6.0 used for this Linux harness does not allow them on value types.
        source = source.replace("nonisolated struct ", "struct ")
        if relative == "Shared/EnforcementTransaction.swift":
            source = source.replace("static func begin(wait: Bool = true) -> Lease? {", "static func begin(wait: Bool = true) -> Lease? { Probe.didBeginLease()")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    if sys.platform == "linux": files.append(root / "Tests/Support/OSLog.swift")
    subprocess.run(["swiftc", "-D", "TYRI_QA_UIKIT", "-parse-as-library", "-module-cache-path", str(temp / "cache"), *map(str, files),
                    "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, timeout=25)
