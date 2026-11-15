import Foundation

@main struct UsageRearmQA {
    static func main() throws {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            print("\(condition ? "PASS" : "FAIL"): \(message)")
            if !condition { failures += 1 }
        }
        let nativeControl = DeviceActivityName(rawValue: "contract.control")
        try DeviceActivityCenter().startMonitoring(nativeControl, during: UsageMonitoring.allDaySchedule)
        DeviceActivityCenter().stopMonitoring([])
        check(DeviceActivityCenter().activities.isEmpty && DeviceActivityCenter.events.isEmpty,
              "Native contract: empty stop array clears all schedules and events")
        DeviceActivityCenter.stopAllCalls = 0
        QAClock.now = Date(timeIntervalSince1970: 1794678232)
        let id = UUID()
        BlockResolution.blocks[id] = BlockRule(id: id, usageLockMinutes: 180, usageLimitMinutes: 10)
        let monitor = TyriMonitorExtension()
        check(UsageMonitoring.startUsageMonitor(forBlockID: id), "Initial 10-minute allowance registers")
        let unrelated = DeviceActivityName(rawValue: "unrelated.schedule")
        try DeviceActivityCenter().startMonitoring(unrelated, during: UsageMonitoring.allDaySchedule)
        for cycle in 1...2 {
            let allowance = UsageMonitoring.usageActivityName(for: id)
            monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: allowance)
            let end = SharedDefaults.suite.object(forKey: SharedDefaults.Keys.usageLockEnd(blockID: id)) as! Date
            check(end.timeIntervalSince(QAClock.now) == 10800, "Cycle \(cycle) preserves 180-minute lock")
            let lock = UsageMonitoring.lockActivityName(for: id)
            QAClock.now = end
            monitor.intervalDidEnd(for: lock)
            let next = UsageMonitoring.usageActivityName(for: id)
            let receipt = SharedDefaults.suite.string(forKey: EnforcementDiagnostics.key("registration", id)) ?? ""
            check(receipt.contains("Registered allowance"), "Cycle \(cycle) produces successful rearm receipt")
            check(next != allowance && DeviceActivityCenter().activities.contains(next),
                  "Cycle \(cycle) rearmed allowance remains registered after cleanup")
            check(DeviceActivityCenter().activities.contains(unrelated), "Cycle \(cycle) preserves unrelated schedule monitor")
            check(DeviceActivityCenter.stopAllCalls == 0, "Cycle \(cycle) never sends a global-stop empty array")
            let starts = DeviceActivityCenter.starts
            monitor.intervalDidEnd(for: lock)
            monitor.eventDidReachThreshold(UsageMonitoring.usageEventName, activity: allowance)
            check(DeviceActivityCenter.starts == starts && UsageMonitoring.usageActivityName(for: id) == next,
                  "Cycle \(cycle) duplicate expiry/stale threshold retain healthy counter")
            // Do not proceed with a synthetic callback from a native-deleted
            // allowance: report the first failure as the minimal recurrence.
            if failures > 0 { break }
        }
        let absent = UUID()
        // Timer-to-tag conversion followed by recovery cleanup leaves an empty
        // inactive ledger; deleting that tag must not stop any other owner.
        UsageMonitoring.stopUsageMonitor(for: absent)
        let lease = EnforcementTransaction.begin()!
        MonitorRegistration.acknowledgeRetired(["usage.\(absent.uuidString)"])
        lease.finish()
        // Independent native controls make the teardown assertion useful even
        // when the earlier expiry regression has already failed.
        let survivors = [unrelated, DeviceActivityName(rawValue: "usage.other-owner"),
                         DeviceActivityName(rawValue: "lock.other-owner"), DeviceActivityName(rawValue: "break.other-owner")]
        for activity in survivors { try DeviceActivityCenter().startMonitoring(activity, during: UsageMonitoring.allDaySchedule) }
        let stopAllBefore = DeviceActivityCenter.stopAllCalls
        UsageMonitoring.stopUsageMonitor(for: absent)
        for activity in survivors {
            check(DeviceActivityCenter().activities.contains(activity), "Acknowledged teardown preserves \(activity.rawValue)")
        }
        check(DeviceActivityCenter.stopAllCalls == stopAllBefore, "Empty retirement set never stops all activities")
        print("RESULT: \(checks - failures)/\(checks) checks passed; \(failures) failures; production callbacks/native-contract double, not actual device counting")
        if failures > 0 { exit(1) }
    }
}
