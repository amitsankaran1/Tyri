// REVIEW-ONLY doubles: deterministic DeviceActivity / ManagedSettings / FamilyControls stand-ins.
import Foundation
enum QAClock { static var now = Date() }
typealias ApplicationToken = Int
typealias WebDomainToken = Int
typealias ActivityCategoryToken = Int
struct FamilyActivitySelection: Codable {
 var applicationTokens: Set<Int> = []; var categoryTokens: Set<Int> = []; var webDomainTokens: Set<Int> = []
 var includeEntireCategory = false
 init(includeEntireCategory: Bool = false) { self.includeEntireCategory = includeEntireCategory }
}
enum WebContentSettings { typealias FilterPolicy = ManagedSettingsStore.Filter }
struct WebDomain: Hashable { let domain: String }
class ManagedSettingsStore {
 struct Name: Hashable { let rawValue: String }
 enum Policy: Equatable { case specific(Set<Int>, except: Set<Int> = []); case all }
 enum Filter: Equatable { case specific(Set<WebDomain>) }
 class Shield { var applications: Set<Int>?; var applicationCategories: Policy?; var webDomains: Set<Int>? }
 class WebContent { var blockedByFilter: Filter? }
 static var saved: [Name: ManagedSettingsStore] = [:]
 var shield = Shield(); var webContent = WebContent()
 init() {}
 convenience init(named name: Name) { self.init(); if let old = Self.saved[name] { shield = old.shield; webContent = old.webContent } else { Self.saved[name] = self } }
 func clearAllSettings() { shield.applications = nil; shield.webDomains = nil; shield.applicationCategories = nil; webContent.blockedByFilter = nil }
}
struct DeviceActivityName: Hashable { let rawValue: String; init(rawValue: String) { self.rawValue = rawValue } }
struct DeviceActivityEvent {
 struct Name: Hashable { let rawValue: String; init(rawValue: String) { self.rawValue = rawValue }; init(_ v: String) { rawValue = v } }
 let applications: Set<Int>; let categories: Set<Int>; let webDomains: Set<Int>; let threshold: DateComponents; let includesPastActivity: Bool
 init(applications: Set<Int>, categories: Set<Int>, webDomains: Set<Int>, threshold: DateComponents, includesPastActivity: Bool = false) {
  self.applications = applications; self.categories = categories; self.webDomains = webDomains; self.threshold = threshold; self.includesPastActivity = includesPastActivity }
}
struct DeviceActivitySchedule { let intervalStart: DateComponents; let intervalEnd: DateComponents; let repeats: Bool; var warningTime: DateComponents? = nil }
class DeviceActivityMonitor {
 func intervalDidStart(for activity: DeviceActivityName) {}
 func intervalDidEnd(for activity: DeviceActivityName) {}
 func intervalWillEndWarning(for activity: DeviceActivityName) {}
 func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {}
}
struct DeviceActivityCenter {
 static var schedules: [DeviceActivityName: DeviceActivitySchedule] = [:]
 var activities: [DeviceActivityName] { Array(Self.schedules.keys) }
 func startMonitoring(_ name: DeviceActivityName, during schedule: DeviceActivitySchedule, events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) throws { Self.schedules[name] = schedule }
 func stopMonitoring(_ names: [DeviceActivityName]) { for n in names { Self.schedules[n] = nil } }
}
