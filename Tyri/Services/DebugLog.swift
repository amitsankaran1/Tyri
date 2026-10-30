//
//  DebugLog.swift
//  Tyri
//
//  In-memory log buffer surfaced in DebugMenuView. Captures Screen Time /
//  DeviceActivity / NFC events so you don't have to watch the Xcode console.
//
//  Compiled out of release builds.
//

#if DEBUG

import Foundation
import Combine

@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    enum Channel: String, CaseIterable, Identifiable {
        case screenTime = "ScreenTime"
        case deviceActivity = "DeviceActivity"
        case nfc = "NFC"
        case cooldown = "Cooldown"
        case actuator = "Actuator"
        case state = "State"

        var id: String { rawValue }

        var emoji: String {
            switch self {
            case .screenTime:     return "🛡️"
            case .deviceActivity: return "📅"
            case .nfc:            return "📡"
            case .cooldown:       return "⏳"
            case .actuator:       return "🎬"
            case .state:          return "📦"
            }
        }
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let channel: Channel
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    private let capacity = 200

    private init() {}

    func log(_ channel: Channel, _ message: String) {
        let entry = Entry(timestamp: Date(), channel: channel, message: message)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        // Mirror to console with the existing emoji style.
        print("\(channel.emoji) [\(channel.rawValue)] \(message)")
    }

    func clear() {
        entries.removeAll()
    }
}

/// Convenience for non-MainActor call sites.
func debugLog(_ channel: DebugLog.Channel, _ message: String) {
    Task { @MainActor in DebugLog.shared.log(channel, message) }
}

#endif
