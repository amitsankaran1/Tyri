import Foundation

/// Tests real callback/registration code, not a second implementation of the
/// state machine. The oracle stores only a deadline created by a known threshold.
@main struct CallbackLifecycleStressQA {
    static func main() {
        let seed = UInt64(ProcessInfo.processInfo.environment["TYRI_CALLBACK_SEED"] ?? "370026601")!
        var random = seed
        func next(_ count: Int) -> Int {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return Int((random >> 32) % UInt64(count))
        }
        let monitor = TyriMonitorExtension()
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000037")!
        let other = UUID(uuidString: "00000000-0000-0000-0000-000000000038")!
        BlockResolution.blocks[id] = BlockRule(id: id, usageLockMinutes: 180, usageLimitMinutes: 10)
        BlockResolution.blocks[other] = BlockRule(id: other, type: .tag, isEnabled: true)
        State.shields.insert(other)
        var trace: [String] = []
        func check(_ condition: Bool, _ message: String) {
            guard condition else {
                print("FAIL seed=\(seed): \(message)\nCycle-local replay trace: \(trace.joined(separator: ", "))")
                exit(1)
            }
        }
        QAClock.now = Date(timeIntervalSince1970: 1794678232)
        check(UsageMonitoring.startUsageMonitor(forBlockID: id), "Initial registration")
        var oldAllowances: [DeviceActivityName] = []
        var oldLocks: [DeviceActivityName] = []
        var transitions = 0
        for cycle in 0..<100 {
            trace = ["cycle \(cycle)"]
            let allowance = UsageMonitoring.usageActivityName(for: id)
            let before = DeviceActivityCenter.starts
            for _ in 0..<next(8) {
                let stale = oldAllowances.isEmpty ? DeviceActivityName(rawValue: "usage.\(id).obsolete") : oldAllowances[next(oldAllowances.count)]
                monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: stale)
                trace.append("stale allowance")
                check(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) == nil,
                      "Stale threshold consumed newer allowance")
                transitions += 1
            }
            check(DeviceActivityCenter.starts == before, "Stale callback reset counter")
            let manual = next(2) == 0
            BlockResolution.blocks[id]!.isEnabled = manual
            let thresholdTime = QAClock.now
            monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: allowance)
            let expectedEnd = Date(timeIntervalSince1970: floor(thresholdTime.timeIntervalSince1970) + 10800)
            let lock = UsageMonitoring.lockActivityName(for: id)
            trace.append("threshold")
            check(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date == expectedEnd,
                  "180-minute lock deadline wrong")
            for _ in 0..<20 {
                QAClock.now = thresholdTime.addingTimeInterval(Double(next(10799)))
                switch next(5) {
                case 0: monitor.intervalDidEnd(for: lock); trace.append("early end")
                case 1: monitor.intervalWillEndWarning(for: lock); trace.append("early warning")
                case 2: monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: allowance); trace.append("duplicate threshold")
                case 3: monitor.intervalDidStart(for: lock); trace.append("late start")
                default:
                    if !oldLocks.isEmpty { monitor.intervalDidEnd(for: oldLocks[next(oldLocks.count)]) }
                    trace.append("old lock end")
                }
                check(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as? Date == expectedEnd,
                      "Callback shortened/extended live lock")
                check(State.shields.contains(id), "Premature unlock")
                check(State.shields.contains(other), "Unrelated owner lost")
                transitions += 1
            }
            QAClock.now = expectedEnd
            monitor.intervalDidEnd(for: lock)
            trace.append("expiry")
            check(SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) == nil, "Expiry never released lock")
            check(State.shields.contains(id) == manual, "Expiry lost manual ownership or retained expired shield")
            check(State.shields.contains(other), "Expiry cleared unrelated owner")
            let nextAllowance = UsageMonitoring.usageActivityName(for: id)
            check(nextAllowance != allowance && DeviceActivityCenter().activities.contains(nextAllowance), "No fresh next allowance")
            let starts = DeviceActivityCenter.starts
            monitor.intervalDidEnd(for: lock)
            monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: allowance)
            check(DeviceActivityCenter.starts == starts && UsageMonitoring.usageActivityName(for: id) == nextAllowance,
                  "Duplicate expiry or old threshold reset next allowance")
            oldAllowances.append(allowance); oldLocks.append(lock)
            transitions += 4
        }
        print("PASS: seed \(seed), 100 complete 10/180 cycles, \(transitions) replayable callback transitions; native calls/shields are doubles")
    }
}
