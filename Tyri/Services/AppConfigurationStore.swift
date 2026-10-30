//
//  AppConfigurationStore.swift
//  Tyri
//
//  Created by Amit Sankaran on 1/7/26.
//

import Foundation
import FamilyControls
import ManagedSettings
import Combine

class AppConfigurationStore: ObservableObject {
    static let shared = AppConfigurationStore()

    @Published var selectedApps: FamilyActivitySelection = FamilyActivitySelection() {
        didSet {
            if !isLoadingFromDefaults {
                debouncedSave()
                // Track that user has selected apps (including categories)
                if !selectedApps.applicationTokens.isEmpty || !selectedApps.categoryTokens.isEmpty {
                    defaults.set(true, forKey: hasSelectedAppsKey)
                }
            }
        }
    }
    @Published var registeredTagIdentifier: String? = nil
    @Published var isBlockingEnabled: Bool = false

    private let selectedAppsKey = SharedDefaults.Keys.selectedApps
    private let hasSelectedAppsKey = SharedDefaults.Keys.hasSelectedApps
    private let registeredTagKey = SharedDefaults.Keys.registeredTag
    private let blockingEnabledKey = SharedDefaults.Keys.blockingEnabled
    private var isLoadingFromDefaults = false
    private var userHasSelectedApps: Bool = false
    private var saveTask: Task<Void, Never>?

    private var defaults: UserDefaults { SharedDefaults.suite }

    private init() {
        AppConfigurationStore.migrateLegacyDefaults()
        loadConfiguration()
    }

    /// Copy legacy keys from `UserDefaults.standard` into the App Group suite on first launch
    /// so existing installs aren't reset. Safe to call multiple times.
    static func migrateLegacyDefaults() {
        let standard = UserDefaults.standard
        let suite = SharedDefaults.suite
        let keys = [
            SharedDefaults.Keys.selectedApps,
            SharedDefaults.Keys.hasSelectedApps,
            SharedDefaults.Keys.registeredTag,
            SharedDefaults.Keys.blockingEnabled
        ]
        for key in keys where suite.object(forKey: key) == nil {
            if let value = standard.object(forKey: key) {
                suite.set(value, forKey: key)
            }
        }
    }

    private func debouncedSave() {
        // Cancel pending save
        saveTask?.cancel()

        // Schedule new save after 300ms
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

            if !Task.isCancelled {
                saveSelectedAppsToUserDefaults()
            }
        }
    }

    private func saveSelectedAppsToUserDefaults() {
        // Cancel any pending save since we're saving now
        saveTask?.cancel()

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(selectedApps)
            defaults.set(data, forKey: selectedAppsKey)
            print("💾 Saved \(selectedApps.applicationTokens.count) apps, \(selectedApps.categoryTokens.count) categories to UserDefaults")
        } catch {
            print("❌ Failed to encode selectedApps: \(error)")
        }
    }

    func saveSelectedApps(_ selection: FamilyActivitySelection) {
        selectedApps = selection
        // Immediately save for explicit API calls (skip debounce)
        saveSelectedAppsToUserDefaults()

        // Track that user has selected apps (including categories)
        if !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty {
            defaults.set(true, forKey: hasSelectedAppsKey)
            userHasSelectedApps = true
        }
    }

    /// Re-decode the saved FamilyActivitySelection from UserDefaults.
    /// Call this after Screen Time authorization is confirmed, since opaque
    /// tokens may only resolve once the app has active authorization.
    func reloadSelectedApps() {
        guard let data = defaults.data(forKey: selectedAppsKey) else {
            print("ℹ️ reloadSelectedApps: no saved data in UserDefaults")
            return
        }
        do {
            let decoder = JSONDecoder()
            isLoadingFromDefaults = true
            let loadedSelection = try decoder.decode(FamilyActivitySelection.self, from: data)
            selectedApps = loadedSelection
            isLoadingFromDefaults = false
            print("🔄 Reloaded FamilyActivitySelection: \(selectedApps.applicationTokens.count) apps, \(selectedApps.categoryTokens.count) categories")
        } catch {
            print("❌ reloadSelectedApps failed to decode: \(error)")
            isLoadingFromDefaults = false
        }
    }

    func clearSelectedApps() {
        selectedApps = FamilyActivitySelection()
        defaults.removeObject(forKey: selectedAppsKey)
        defaults.set(false, forKey: hasSelectedAppsKey)
        userHasSelectedApps = false
    }

    func registerTag(identifier: String) {
        registeredTagIdentifier = identifier
        defaults.set(identifier, forKey: registeredTagKey)
    }

    func clearTagRegistration() {
        registeredTagIdentifier = nil
        defaults.removeObject(forKey: registeredTagKey)
    }

    func setBlockingEnabled(_ enabled: Bool) {
        isBlockingEnabled = enabled
        defaults.set(enabled, forKey: blockingEnabledKey)
    }

    func toggleBlocking() {
        setBlockingEnabled(!isBlockingEnabled)
    }

    private func loadConfiguration() {
        registeredTagIdentifier = defaults.string(forKey: registeredTagKey)
        isBlockingEnabled = defaults.bool(forKey: blockingEnabledKey)
        userHasSelectedApps = defaults.bool(forKey: hasSelectedAppsKey)

        print("🔄 Loading configuration...")
        print("   - Tag registered: \(registeredTagIdentifier != nil)")
        print("   - Blocking enabled: \(isBlockingEnabled)")
        print("   - User has selected apps: \(userHasSelectedApps)")

        // Load selectedApps from UserDefaults
        if let data = defaults.data(forKey: selectedAppsKey) {
            do {
                let decoder = JSONDecoder()
                isLoadingFromDefaults = true
                let loadedSelection = try decoder.decode(FamilyActivitySelection.self, from: data)

                // Note: applicationTokens might be empty if authorization is not granted yet
                // but the selection object is still valid and will work once authorized
                selectedApps = loadedSelection
                isLoadingFromDefaults = false

                print("✅ Loaded FamilyActivitySelection from UserDefaults")
                print("   - Application tokens count: \(selectedApps.applicationTokens.count)")
                print("   - Category tokens count: \(selectedApps.categoryTokens.count)")

                // If tokens are empty but we know user selected apps, it means authorization is needed
                let allTokensEmpty = selectedApps.applicationTokens.isEmpty && selectedApps.categoryTokens.isEmpty
                if allTokensEmpty && userHasSelectedApps {
                    print("⚠️ Selection loaded but tokens empty - may need re-authorization")
                }
            } catch {
                print("❌ Failed to decode selectedApps: \(error)")
                isLoadingFromDefaults = false
                selectedApps = FamilyActivitySelection()
            }
        } else {
            print("ℹ️ No saved app selection found in UserDefaults")
        }
    }

    var hasSelectedApps: Bool {
        // Check if there are actual tokens (apps or categories) OR if user has previously selected apps
        // (tokens might be empty temporarily if authorization is pending)
        !selectedApps.applicationTokens.isEmpty || !selectedApps.categoryTokens.isEmpty || userHasSelectedApps
    }

    var isTagRegistered: Bool {
        registeredTagIdentifier != nil
    }
}
