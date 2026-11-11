import Foundation

/// Confirmed threshold milestones, not a wall-clock estimate of app usage.
struct UsageProgress: Codable {
    let generation: String
    let day: Date
    let minutes: Int

    static func key(_ id: UUID) -> String { "usageProgress.\(id.uuidString)" }
    static func step(for limit: Int) -> Int {
        // At most 60 progress events per monitor, alongside the enforcement event.
        max(1, Int(ceil(Double(limit) / 60)))
    }
    static func milestones(for limit: Int) -> [Int] {
        guard limit > 1 else { return [] }
        return Array(stride(from: step(for: limit), to: limit, by: step(for: limit)))
    }
    static func reported(blockID: UUID, now: Date = Date()) -> Int? {
        let suite = SharedDefaults.suite
        guard let data = suite.data(forKey: key(blockID)),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.generation == suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID)) else { return nil }
        return Calendar.current.isDate(value.day, inSameDayAs: now) ? value.minutes : nil
    }
    static func record(_ minutes: Int, blockID: UUID, reset: Bool = false, now: Date = Date()) {
        guard let generation = SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageGeneration(blockID: blockID)) else { return }
        let value = Self(generation: generation, day: Calendar.current.startOfDay(for: now),
                         minutes: reset ? minutes : max(minutes, reported(blockID: blockID, now: now) ?? 0))
        if let data = try? JSONEncoder().encode(value) { SharedDefaults.suite.set(data, forKey: key(blockID)) }
    }
}
