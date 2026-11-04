import Foundation

enum SharedDefaults {
    static let name = "Tyri.UsageProgressQA.\(UUID().uuidString)"
    static let suite = UserDefaults(suiteName: name)!
    enum Keys { static func usageGeneration(blockID: UUID) -> String { "generation.\(blockID)" } }
}
defer { SharedDefaults.suite.removePersistentDomain(forName: SharedDefaults.name) }
let id = UUID(), now = Date()
SharedDefaults.suite.set("first", forKey: SharedDefaults.Keys.usageGeneration(blockID: id))
precondition(UsageProgress.reported(blockID: id) == nil)
UsageProgress.record(0, blockID: id, reset: true, now: now)
precondition(UsageProgress.reported(blockID: id, now: now) == 0)
UsageProgress.record(4, blockID: id, now: now)
UsageProgress.record(2, blockID: id, now: now)
precondition(UsageProgress.reported(blockID: id, now: now) == 4)
let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
precondition(UsageProgress.reported(blockID: id, now: tomorrow) == 0)
UsageProgress.record(1, blockID: id, now: tomorrow)
precondition(UsageProgress.reported(blockID: id, now: tomorrow) == 1)
SharedDefaults.suite.set("second", forKey: SharedDefaults.Keys.usageGeneration(blockID: id))
precondition(UsageProgress.reported(blockID: id, now: tomorrow) == nil)
UsageProgress.record(0, blockID: id, reset: true, now: tomorrow)
precondition(UsageProgress.reported(blockID: id, now: tomorrow) == 0)
for limit in stride(from: 5, through: 1435, by: 5) {
 let points = UsageProgress.milestones(for: limit)
 precondition(points.count <= 60 && points.allSatisfy { $0 > 0 && $0 < limit })
 precondition(points == points.sorted() && Set(points).count == points.count)
}
precondition(UsageProgress.milestones(for: 5) == [1,2,3,4])
print("PASS: reported progress, generation invalidation, daily reset, and all 287 duration milestone ranges")
