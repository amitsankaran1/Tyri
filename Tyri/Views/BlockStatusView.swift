import SwiftUI
import FamilyControls

/// Presentation only: never changes a block's enforcement or usage budget.
struct BlockStatusPresentation {
    enum State { case blocking, tracking, paused, off, setup, unavailable }
    let state: State
    let detail: String
    var end: Date? = nil
    // Populated only by the explicitly enabled simulator review fixture until
    // per-cycle usage measurement is integrated. Never infer usage from wall time.
    var usedMinutes: Int? = nil
    var limitMinutes: Int? = nil

    var title: String {
        switch state {
        case .blocking: return "Blocking on"
        case .tracking: return "Tracking usage"
        case .paused: return "On a break"
        case .off: return "Blocking off"
        case .setup: return "Screen Time access needed"
        case .unavailable: return "Tracking unavailable"
        }
    }
    var color: Color {
        switch state {
        case .blocking: return .red
        case .tracking: return .blue
        case .paused: return .orange
        case .off, .setup, .unavailable: return .secondary
        }
    }
    var icon: String {
        switch state {
        case .blocking: return "lock.fill"
        case .tracking: return "hourglass"
        case .paused: return "pause.fill"
        case .off: return "lock.open"
        case .setup, .unavailable: return "exclamationmark.circle"
        }
    }

    @MainActor
    static var canDisplayActivity: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if reviewScenario != nil { return true }
        #endif
        return ScreenTimeManager.shared.authorizationStatus == .approved
    }

    @MainActor
    static func current(for block: BlockRule) -> Self {
        #if DEBUG && targetEnvironment(simulator)
        if let sample = reviewStatus(for: block) { return sample }
        #endif
        guard canDisplayActivity else {
            return Self(state: .setup, detail: "Allow access in Settings to start this block.")
        }
        if BreakMonitoring.isOnBreak(blockID: block.id) {
            return Self(state: .paused, detail: "Blocking resumes automatically.", end: BreakMonitoring.breakEnd(blockID: block.id))
        }
        if ScreenTimeManager.shared.isBlockActive(block) {
            let timedEnd = UsageLimitManager.shared.lockEnd(for: block.id) ?? block.schedule?.activeWindow()?.end
            let end = block.isEnabled ? nil : timedEnd
            var detail = BlockingEndDescription.detail(timedEnd: timedEnd, manual: block.isEnabled, tag: block.type == .tag)
            if let wait = CooldownManager.shared.activeCooldown, wait.blockID == block.id {
                detail += " " + (wait.endsAt > Date()
                    ? "Apps stay blocked. You can stop early at \(wait.endsAt.formatted(date: .omitted, time: .shortened))."
                    : "Wait complete. Open this block to stop it early.")
            }
            return Self(state: .blocking, detail: detail, end: end)
        }
        if block.type == .timer {
            if let error = SharedDefaults.suite.string(forKey: SharedDefaults.Keys.usageError(blockID: block.id)) {
                return Self(state: .unavailable, detail: error)
            }
            guard UsageMonitoring.isUsageMonitorActive(for: block.id) else {
                return Self(state: .unavailable, detail: "Open this block to check its app lists and save to retry.")
            }
            return Self(state: .tracking, detail: "Counts usage toward your next pause.", limitMinutes: block.usageLimitMinutes)
        }
        return Self(state: .off, detail: block.type == .tag ? "Start with your NFC tag" : block.schedule?.summary ?? "No schedule set")
    }

    #if DEBUG && targetEnvironment(simulator)
    private static let reviewStart = Date()
    static var reviewScenario: String? {
        guard ProcessInfo.processInfo.environment["BLOCK_SEED_DEMO_STATE"] == "1" else { return nil }
        return ProcessInfo.processInfo.environment["TYRI_UI_REVIEW"]
    }

    private static func reviewStatus(for block: BlockRule) -> Self? {
        guard let scenario = reviewScenario else { return nil }
        if block.type == .timer && scenario != "off" {
            if scenario == "locked" {
                return Self(state: .blocking, detail: BlockingEndDescription.detail(timedEnd: reviewStart.addingTimeInterval(10800), manual: false, tag: false), end: reviewStart.addingTimeInterval(10800))
            }
            return Self(state: .tracking, detail: "Counts usage toward your next pause.", usedMinutes: 9, limitMinutes: 30)
        }
        if block.type == .schedule {
            if scenario == "blocking" || scenario == "mixed" {
                return Self(state: .blocking, detail: "Until 5:00 PM")
            }
            if scenario == "break" {
                return Self(state: .paused, detail: "Blocking resumes automatically.", end: reviewStart.addingTimeInterval(300))
            }
        }
        if block.type == .tag && scenario == "mixed" {
            return Self(state: .paused, detail: "Blocking resumes automatically.", end: reviewStart.addingTimeInterval(300))
        }
        return Self(state: .off, detail: block.type == .schedule ? "Weekdays · 9:00 AM–5:00 PM" : block.type == .timer ? "No usage limit running" : "Start with your NFC tag")
    }
    #endif
}

struct UsageProgressView: View {
    let used: Int?
    let limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let used {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(used) of \(limit) min used").font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Text("\(max(0, limit - used)) min left").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(used), total: Double(max(1, limit))).tint(.blue)
                    .accessibilityLabel("Usage")
                    .accessibilityValue("\(used) of \(limit) minutes used")
            } else {
                Text("\(limit) min allowance · Usage so far unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct BlockStatusCard: View {
    let status: BlockStatusPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(status.title, systemImage: status.icon)
                .font(.title2.bold()).foregroundStyle(status.color)
                .accessibilityIdentifier("focus-status-title")
            Text(status.detail).font(.subheadline).foregroundStyle(.secondary)
            if let end = status.end, status.state == .paused {
                HStack(spacing: 4) {
                    Text("Resumes in")
                    Text(end, style: .timer).monospacedDigit()
                }.font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(status.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }
}
