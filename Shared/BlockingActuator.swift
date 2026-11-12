//
//  BlockingActuator.swift
//  Tyri
//
//  Shared shielding logic for a block. Used by:
//    - TyriMonitorExtension (real device, on schedule / threshold)
//    - DebugSimulator (in-process, for simulator/dev testing)
//
//  A block's shield = the union of its referenced AppGroups' tokens
//  (see BlockResolution). Add target membership to BOTH Tyri and TyriMonitor.
//

import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import ManagedSettings
import FamilyControls

enum BlockingActuator {

    private struct Intent: Codable, Equatable {
        var tokens: BlockResolution.Tokens?
        var includeCategories = true
        var revision = UUID()
        var applied = false
        var chunks = 1
        // A newer writer cannot declare success while an older native write is
        // still able to land. Orphaned operations deliberately keep recovery
        // retryable after a process dies; safety takes priority over caching.
        var inFlight: Set<UUID> = []
        var processOwners: [String: Int32]? = nil

        mutating func retireDeadWriters() {
            for operation in inFlight {
                guard let pid = processOwners?[operation.uuidString], kill(pid, 0) == -1, errno == ESRCH else { continue }
                inFlight.remove(operation)
                processOwners?.removeValue(forKey: operation.uuidString)
                applied = false
            }
        }
    }
    private static let lifecycleMutex = NSLock()
    private static var effectsEnabled = true
    private static var activation = UUID()
    private static var finishedWhileInactive: [UUID: Set<UUID>] = [:]
    private static var verified: [UUID: (revision: UUID, activation: UUID)] = [:]

    /// App lifecycle only. The monitor extension has its own process and remains
    /// enabled. Pending intent survives suspension and is retried on foreground.
    static func setEffectsEnabled(_ enabled: Bool) {
        lifecycleMutex.lock()
        if enabled && !effectsEnabled { activation = UUID() }
        effectsEnabled = enabled
        lifecycleMutex.unlock()
    }
    private static var canApply: Bool {
        lifecycleMutex.lock(); defer { lifecycleMutex.unlock() }; return effectsEnabled
    }
    private static func effectLease() -> EnforcementTransaction.Lease? {
        // Extension callbacks have no foreground timer to retry a dropped write.
        // Wait without owning a file lease, and keep lifecycle rejection distinct
        // from transient contention. Resignation/expiration ends this retry lane.
        while true {
            lifecycleMutex.lock()
            guard effectsEnabled else { lifecycleMutex.unlock(); return nil }
            let lease = EnforcementTransaction.begin(wait: false)
            lifecycleMutex.unlock()
            if let lease { return lease }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    private static func deferCompletion(_ operation: UUID, for id: UUID) {
        lifecycleMutex.lock(); defer { lifecycleMutex.unlock() }
        finishedWhileInactive[id, default: []].insert(operation)
    }

    static var persistedOwnerIDs: Set<UUID> {
        let prefixes = ["shieldIntent.v1.", "usagelock.", "running.", "manualActivation."]
        return Set(SharedDefaults.suite.dictionaryRepresentation().keys.compactMap { key in
            guard let prefix = prefixes.first(where: { key.hasPrefix($0) }) else { return nil }
            return UUID(uuidString: String(key.dropFirst(prefix.count)))
        })
    }

    private static func intentKey(_ id: UUID) -> String { "shieldIntent.v1.\(id.uuidString)" }
    private static func loadIntent(_ id: UUID) -> Intent? {
        SharedDefaults.suite.data(forKey: intentKey(id)).flatMap { try? JSONDecoder().decode(Intent.self, from: $0) }
    }
    private static func saveIntent(_ intent: Intent, _ id: UUID) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        SharedDefaults.suite.set(data, forKey: intentKey(id))
    }
    private static func submit(tokens: BlockResolution.Tokens?, blockID: UUID, includeCategories: Bool = true) {
        guard let lease = EnforcementTransaction.begin() else { return }
        defer { lease.finish() }
        let old = loadIntent(blockID)
        if old?.tokens != tokens || old?.includeCategories != includeCategories || old == nil {
            // Retain the high-water chunk count until the new intent completes.
            let count = max(old?.chunks ?? 1,
                SharedDefaults.suite.integer(forKey: SharedDefaults.Keys.shieldChunkCount(blockID: blockID)),
                tokens.map { max(1, ($0.apps.count + 49) / 50, ($0.webDomains.count + 49) / 50) } ?? 1)
            saveIntent(Intent(tokens: tokens, includeCategories: includeCategories,
                              chunks: min(maxChunksPerBlock, count), inFlight: old?.inFlight ?? [], processOwners: old?.processOwners), blockID)
        }
        EnforcementTransaction.afterUnlock(key: intentKey(blockID)) { flushIntent(blockID) }
    }

    /// Replays tombstones too: expired/deleted owners no longer appear in the
    /// block/session enumeration, but their deferred clears must still complete.
    static func replayPending() {
        guard let lease = EnforcementTransaction.begin(wait: false) else { return }
        defer { lease.finish() }
        let prefix = "shieldIntent.v1."
        lifecycleMutex.lock()
        let completed = finishedWhileInactive
        finishedWhileInactive.removeAll()
        lifecycleMutex.unlock()
        for (id, operations) in completed {
            if var intent = loadIntent(id) {
                intent.inFlight.subtract(operations)
                for operation in operations { intent.processOwners?.removeValue(forKey: operation.uuidString) }
                intent.applied = false
                saveIntent(intent, id)
            }
        }
        for key in SharedDefaults.suite.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard let id = UUID(uuidString: String(key.dropFirst(prefix.count))) else { continue }
            EnforcementTransaction.afterUnlock(key: key) { flushIntent(id) }
        }
    }

    /// Native calls run without the interprocess lease. Each completion compares
    /// its revision with durable intent: an app/extension edit during stalled IPC
    /// causes the latest intent to be replayed, never an obsolete acknowledgement.
    private static func flushIntent(_ id: UUID) {
        var force = false
        while canApply {
            guard let lease = effectLease() else { return }
            guard var intent = loadIntent(id) else { lease.finish(); return }
            intent.retireDeadWriters()
            lifecycleMutex.lock()
            let epoch = activation
            let cached = verified[id]
            lifecycleMutex.unlock()
            guard force || !intent.applied || cached?.revision != intent.revision || cached?.activation != epoch else {
                lease.finish(); return
            }
            guard canApply else { lease.finish(); return }
            let operation = UUID()
            intent.inFlight.insert(operation)
            if intent.processOwners == nil { intent.processOwners = [:] }
            intent.processOwners?[operation.uuidString] = ProcessInfo.processInfo.processIdentifier
            intent.applied = false
            saveIntent(intent, id)
            lease.finish()
            let result: (matched: Bool, chunks: Int, audit: String?, error: String?)?
            if let tokens = intent.tokens {
                result = write(tokens: tokens, blockID: id, includeCategories: intent.includeCategories,
                               oldCount: intent.chunks)
            } else {
                for i in 0..<intent.chunks {
                    guard canApply else { deferCompletion(operation, for: id); return }
                    ManagedSettingsStore(named: appsStoreName(for: id, chunk: i)).clearAllSettings()
                }
                guard canApply else { deferCompletion(operation, for: id); return }
                ManagedSettingsStore(named: categoriesStoreName(for: id)).clearAllSettings()
                result = (true, 1, nil, nil)
            }
            guard let result, let completion = effectLease() else {
                deferCompletion(operation, for: id)
                return
            }
            guard var current = loadIntent(id) else { completion.finish(); return }
            current.inFlight.remove(operation)
            current.processOwners?.removeValue(forKey: operation.uuidString)
            current.retireDeadWriters()
            guard current.revision == intent.revision else {
                current.applied = false
                saveIntent(current, id)
                completion.finish()
                force = true
                continue
            }
            current.applied = result.matched && current.inFlight.isEmpty
            current.chunks = current.inFlight.isEmpty ? result.chunks : max(current.chunks, result.chunks)
            if current.tokens == nil, current.applied, let blocks = BlockResolution.loadBlocks(), !blocks.contains(where: { $0.id == id }) {
                // No live older writer can land and this owner no longer exists.
                // Compaction keeps recovery proportional to current rules/sessions.
                SharedDefaults.suite.removeObject(forKey: intentKey(id))
            } else { saveIntent(current, id) }
            if intent.tokens == nil {
                SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.shieldChunkCount(blockID: id))
            } else {
                SharedDefaults.suite.set(result.chunks, forKey: SharedDefaults.Keys.shieldChunkCount(blockID: id))
            }
            if let audit = result.audit { SharedDefaults.suite.set(audit, forKey: SharedDefaults.Keys.shieldAudit(blockID: id)) }
            if let error = result.error { SharedDefaults.suite.set(error, forKey: SharedDefaults.Keys.shieldError(blockID: id)) }
            else { SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.shieldError(blockID: id)) }
            EnforcementDiagnostics.record("shield", blockID: id,
                detail: result.matched ? "Settings readback matched; effective shielding still requires a device check" : "Settings readback MISMATCH")
            completion.finish()
            if current.applied {
                lifecycleMutex.lock(); verified[id] = (current.revision, epoch); lifecycleMutex.unlock()
            }
            return // A mismatch retries on the next recovery, never a tight loop.
        }
    }

    /// Apply the block's shield to its named store.
    /// Mirrors `TyriMonitorExtension.intervalDidStart` so simulator and device
    /// behavior stay in lockstep.
    ///
    /// - Parameter setRunningFlag: when `true` (scheduled blocks), marks the
    ///   `running` flag that drives the home "Scheduled" display. The usage-lock
    ///   path passes `false` — usage locks are tracked separately via
    ///   `usageLockEnd`, so they must not masquerade as scheduled blocks.
    /// - Parameter resetBreakAllowance: a fresh activation cancels any stale break
    ///   and re-arms the one-break-per-activation allowance. The break re-lock path
    ///   passes `false` — re-shielding after a break must not grant another break.
    @discardableResult
    static func start(blockID: UUID, bypassWeekday: Bool = false, setRunningFlag: Bool = true, resetBreakAllowance: Bool = true) -> Bool {
        guard let transition = EnforcementTransaction.begin() else { return false }
        defer { transition.finish() }

        guard let block = BlockResolution.loadBlock(id: blockID),
              let groups = BlockResolution.loadGroups(),
              Set(block.appGroupIDs).isSubset(of: Set(groups.map(\.id))) else { return false }

        if !bypassWeekday, block.type == .schedule, let schedule = block.schedule {
            let weekday = Calendar.current.component(.weekday, from: Date())
            guard schedule.weekdays.contains(weekday) else { return false }
        }

        if resetBreakAllowance {
            BreakMonitoring.resetAllowance(blockID: blockID)
        }

        let tokens = BlockResolution.tokens(for: block, groups: groups)
        apply(tokens: tokens, blockID: blockID)

        if setRunningFlag {
            SharedDefaults.suite.set(true, forKey: SharedDefaults.Keys.running(blockID: blockID))
        }
        return true
    }

    /// Clear the block's shield and running flag. Mirrors `intervalDidEnd`.
    /// Also tears down any in-flight break — a window that ends mid-break must not
    /// leave a pending re-lock window or stale break state behind.
    static func end(blockID: UUID, stopMonitoring: Bool = true) {
        guard let transition = EnforcementTransaction.begin() else { return }
        defer { transition.finish() }

        BreakMonitoring.resetAllowance(blockID: blockID, stopMonitoring: stopMonitoring)
        clearShields(blockID: blockID)
        SharedDefaults.suite.removeObject(forKey: SharedDefaults.Keys.running(blockID: blockID))
    }

    /// `shield.applications` (and `shield.webDomains`) silently fails — the whole
    /// property is dropped — when given more than 50 tokens, so each chunk store
    /// holds at most 50. iOS unions shields across stores.
    static let tokensPerStore = 50
    /// Bound on chunk stores per block (400 apps + 400 domains). Apple caps an app
    /// and its extensions at 50 stores total, so blocks can't grow stores unbounded.
    static let maxChunksPerBlock = 8

    /// Apply token sets across the block's physical stores. iOS unions shields across
    /// stores; setting `shield.applications` and `shield.applicationCategories =
    /// .specific(...)` on the *same* store has been observed to drop the
    /// individual-apps shield, so categories live in their own store — written first,
    /// so that if any last-writer interaction between the two shield kinds exists,
    /// the individual-app stores win. Apps and web domains are chunked across
    /// `tokensPerStore`-sized stores. Typed-in domains are enforced via the content
    /// filter on chunk 0. Every property is written unconditionally (nil when empty),
    /// and stores from a previous, larger apply are cleared so re-applying a shrunken
    /// selection leaves no stale shields.
    ///
    /// After writing, every store is read back and the result persisted to
    /// `shieldAudit` — the >50-token failure mode drops the property *silently*, so
    /// a mismatch here is the only signal short of tapping a blocked app.
    ///
    /// - Parameter includeCategories: DEBUG diagnostics only — `false` skips (and
    ///   clears) the categories store, to isolate whether a `.specific` categories
    ///   shield suppresses sibling stores' app shields on device.
    static func apply(tokens: BlockResolution.Tokens, blockID: UUID, includeCategories: Bool = true) {
        submit(tokens: tokens, blockID: blockID, includeCategories: includeCategories)
    }

    private static func write(tokens: BlockResolution.Tokens, blockID: UUID, includeCategories: Bool,
                              oldCount: Int) -> (matched: Bool, chunks: Int, audit: String?, error: String?)? {
        let overCapacity = tokens.apps.count > maxChunksPerBlock * tokensPerStore || tokens.webDomains.count > maxChunksPerBlock * tokensPerStore
        let empty = tokens.apps.isEmpty && tokens.categories.isEmpty && tokens.webDomains.isEmpty && tokens.domains.isEmpty
        var appChunks = chunks(tokens.apps, size: tokensPerStore)
        var webChunks = chunks(tokens.webDomains, size: tokensPerStore)
        if appChunks.count > maxChunksPerBlock || webChunks.count > maxChunksPerBlock {
            print("⚠️ BlockingActuator: selection exceeds \(maxChunksPerBlock * tokensPerStore) tokens; truncating (\(tokens.apps.count) apps, \(tokens.webDomains.count) domains)")
            appChunks = Array(appChunks.prefix(maxChunksPerBlock))
            webChunks = Array(webChunks.prefix(maxChunksPerBlock))
        }
        let newCount = max(1, appChunks.count, webChunks.count)

        let categoriesStore = ManagedSettingsStore(named: categoriesStoreName(for: blockID))
        guard canApply else { return nil }
        categoriesStore.shield.applications = nil
        guard canApply else { return nil }
        categoriesStore.shield.applicationCategories = (tokens.categories.isEmpty || !includeCategories)
            ? nil
            : .specific(tokens.categories)

        for i in 0..<newCount {
            let store = ManagedSettingsStore(named: appsStoreName(for: blockID, chunk: i))
            guard canApply else { return nil }
            store.shield.applications = i < appChunks.count ? appChunks[i] : nil
            guard canApply else { return nil }
            store.shield.applicationCategories = nil
            guard canApply else { return nil }
            store.shield.webDomains = i < webChunks.count ? webChunks[i] : nil
            // Typed-in domains have no picker token; the content filter blocks them in
            // Safari (incl. private browsing) with no "allow anyway" escape. Kept on
            // chunk 0 (always present); nil elsewhere so it never goes stale.
            guard canApply else { return nil }
            store.webContent.blockedByFilter = (i == 0 && !tokens.domains.isEmpty)
                ? .specific(Set(tokens.domains.map { WebDomain(domain: $0) }))
                : nil
        }
        for i in newCount..<max(newCount, oldCount) {
            guard canApply else { return nil }
            ManagedSettingsStore(named: appsStoreName(for: blockID, chunk: i)).clearAllSettings()
        }

        guard let (matched, audit) = auditApply(blockID: blockID, appChunks: appChunks, webChunks: webChunks,
                   expectedCategories: includeCategories ? tokens.categories : [], expectedDomains: tokens.domains) else { return nil }
        let error: String? = empty ? "This block has no apps or websites to block. Check its lists."
            : overCapacity ? "This selection is too large to block completely. Reduce the number of selected apps or websites."
            : !matched ? "iOS did not retain all blocking settings. Check Screen Time access and reselect the affected apps."
            : nil
        return (matched, newCount, audit, error)
    }

    /// Read every store back and persist a summary; print loudly on mismatch.
    private static func auditApply(blockID: UUID, appChunks: [Set<ApplicationToken>], webChunks: [Set<WebDomainToken>], expectedCategories: Set<ActivityCategoryToken>, expectedDomains: Set<String>) -> (Bool, String)? {
        let newCount = max(1, appChunks.count, webChunks.count)
        var parts: [String] = []
        var mismatch = false
        for i in 0..<newCount {
            guard canApply else { return nil }
            let store = ManagedSettingsStore(named: appsStoreName(for: blockID, chunk: i))
            let expApps = i < appChunks.count ? appChunks[i].count : 0
            let expWeb = i < webChunks.count ? webChunks[i].count : 0
            let gotApps = store.shield.applications?.count ?? 0
            let gotWeb = store.shield.webDomains?.count ?? 0
            if (store.shield.applications ?? []) != (i < appChunks.count ? appChunks[i] : []) || (store.shield.webDomains ?? []) != (i < webChunks.count ? webChunks[i] : []) { mismatch = true }
            parts.append("chunk\(i) apps \(gotApps)/\(expApps) web \(gotWeb)/\(expWeb)")
        }
        guard canApply else { return nil }
        let gotCategories: Int
        switch ManagedSettingsStore(named: categoriesStoreName(for: blockID)).shield.applicationCategories {
        case .specific(let set, _):
            gotCategories = set.count
            if set != expectedCategories { mismatch = true }
        case .all:                  gotCategories = -1 // "all" — never written by us
        case nil:                   gotCategories = 0
        default:                    gotCategories = -2
        }
        if gotCategories != expectedCategories.count { mismatch = true }
        parts.append("cats \(gotCategories)/\(expectedCategories.count)")
        guard canApply else { return nil }
        let filter = ManagedSettingsStore(named: appsStoreName(for: blockID)).webContent.blockedByFilter
        let expectedFilter: WebContentSettings.FilterPolicy? = expectedDomains.isEmpty ? nil : .specific(Set(expectedDomains.map { WebDomain(domain: $0) }))
        if filter != expectedFilter { mismatch = true }
        parts.append("typed domains \(filter == expectedFilter ? "matched" : "MISMATCH")")

        let summary = (mismatch ? "MISMATCH · " : "") + parts.joined(separator: " · ")
        if mismatch {
            print("⚠️ BlockingActuator: shield readback mismatch for \(blockID): \(summary)")
        }
        return (!mismatch, summary)
    }

    /// Current readback of every store the block occupies (debug inspector).
    static func audit(blockID: UUID) -> String {
        let count = max(1, SharedDefaults.suite.integer(forKey: SharedDefaults.Keys.shieldChunkCount(blockID: blockID)))
        var parts: [String] = []
        for i in 0..<count {
            let store = ManagedSettingsStore(named: appsStoreName(for: blockID, chunk: i))
            parts.append("chunk\(i): \(store.shield.applications?.count ?? 0) apps, \(store.shield.webDomains?.count ?? 0) web")
        }
        switch ManagedSettingsStore(named: categoriesStoreName(for: blockID)).shield.applicationCategories {
        case .specific(let set, _): parts.append("cats: \(set.count)")
        case .all:                  parts.append("cats: all")
        case nil:                   parts.append("cats: none")
        default:                    parts.append("cats: ?")
        }
        return parts.joined(separator: " · ")
    }

    /// Clear every store the block's shield occupies (all app/webDomain chunks plus
    /// the categories store). A missing chunk count means at most the legacy single
    /// apps store was written, so chunk 0 + cats is exactly the right set.
    static func clearShields(blockID: UUID) {
        submit(tokens: nil, blockID: blockID)
    }

    // MARK: - Helpers

    /// Slice a token set into `size`-sized sets. Order is arbitrary; only membership
    /// matters since every apply rewrites all chunks.
    static func chunks<T: Hashable>(_ set: Set<T>, size: Int) -> [Set<T>] {
        guard !set.isEmpty else { return [] }
        let elements = Array(set)
        return stride(from: 0, to: elements.count, by: size).map {
            Set(elements[$0..<min($0 + size, elements.count)])
        }
    }

    /// Chunk `i` of the stores holding `shield.applications` + `shield.webDomains`.
    /// Chunk 0 keeps the legacy `block.<UUID>` name so shields that were active
    /// before chunking shipped stay attached to the same store across an update.
    static func appsStoreName(for blockID: UUID, chunk: Int = 0) -> ManagedSettingsStore.Name {
        chunk == 0
            ? ManagedSettingsStore.Name(rawValue: "block.\(blockID.uuidString)")
            : ManagedSettingsStore.Name(rawValue: "block.\(blockID.uuidString).apps.\(chunk)")
    }

    /// Companion store holding `shield.applicationCategories`.
    static func categoriesStoreName(for blockID: UUID) -> ManagedSettingsStore.Name {
        ManagedSettingsStore.Name(rawValue: "block.\(blockID.uuidString).cats")
    }
}
