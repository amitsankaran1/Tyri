//
//  NFCManager.swift
//  Tyri
//
//  Created by Amit Sankaran on 1/7/26.
//

import Foundation
@preconcurrency import CoreNFC
import Combine

@MainActor
class NFCManager: NSObject, ObservableObject {
    static let shared = NFCManager()

    @Published var isScanning = false
    @Published var lastScannedTag: String? = nil
    @Published var errorMessage: String? = nil

    private var session: NFCTagReaderSession?
    private let configStore = AppConfigurationStore.shared
    private let screenTimeManager = ScreenTimeManager.shared

    var onTagScanned: ((String) -> Void)?

    override private init() {
        super.init()
        setupDefaultCallback()
    }

    func setupDefaultCallback() {
        onTagScanned = { tagId in
            let configStore = AppConfigurationStore.shared
            if let registeredTag = configStore.registeredTagIdentifier {
                if tagId == registeredTag {
                    NFCManager.shared.toggleTagBlocks()
                } else {
                    print("❌ Scanned tag doesn't match registered tag")
                }
            } else {
                // No tag registered yet — register this one.
                configStore.registerTag(identifier: tagId)
            }
        }
    }

    /// Tapping the registered tag toggles every `.tag`-type block together: if any
    /// is currently on, turn them all off; otherwise turn them all on.
    func toggleTagBlocks() {
        let tagBlocks = BlockStore.shared.blocks(ofType: .tag)
        guard !tagBlocks.isEmpty else {
            #if DEBUG
            DebugLog.shared.log(.nfc, "tag tapped but no tag blocks configured")
            #endif
            return
        }
        let anyOn = tagBlocks.contains { $0.isEnabled }
        for block in tagBlocks {
            BlockStore.shared.setEnabled(id: block.id, enabled: !anyOn)
            if anyOn {
                ScreenTimeManager.shared.clearBlockShield(id: block.id)
            } else {
                // A fresh tag session re-arms the one-break allowance.
                BreakMonitoring.resetAllowance(blockID: block.id)
                ScreenTimeManager.shared.applyBlockShield(block)
            }
        }
        BlockStore.shared.flush()
        #if DEBUG
        DebugLog.shared.log(.nfc, "toggled \(tagBlocks.count) tag block(s) → \(anyOn ? "off" : "on")")
        #endif
    }

    func startScanning() {
        guard NFCTagReaderSession.readingAvailable else {
            errorMessage = "NFC reading is not available on this device"
            return
        }

        isScanning = true
        errorMessage = nil

        session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: nil)
        session?.alertMessage = "Hold your iPhone near the NFC tag"
        session?.begin()
    }

    func stopScanning() {
        session?.invalidate()
        session = nil
        isScanning = false
    }

    func simulateTagScan(withId identifier: String) {
        lastScannedTag = identifier

        let wasRegistered = configStore.registeredTagIdentifier != nil

        #if DEBUG
        DebugLog.shared.log(.nfc, "simulateTagScan id=\(identifier) (wasRegistered=\(wasRegistered))")
        #endif

        // Mirror production foreground behavior: dispatch a single callback.
        // (Previously we also invoked handleBackgroundTag, which double-toggled
        // and silently masked failures whenever auth wasn't approved.)
        onTagScanned?(identifier)
    }
}

extension NFCManager: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false

            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled:
                    break
                case .readerSessionInvalidationErrorSessionTimeout:
                    self.errorMessage = "Session timed out. Please try again."
                default:
                    self.errorMessage = "NFC error: \(nfcError.localizedDescription)"
                }
            } else {
                self.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else {
            return
        }

        // CoreNFC's connect completion is @Sendable but NFCTagReaderSession/NFCTag
        // aren't Sendable; these bindings opt out of the capture check (the
        // delegate guarantees single-threaded use here).
        nonisolated(unsafe) let session = session
        nonisolated(unsafe) let tag = firstTag
        session.connect(to: tag) { error in
            if error != nil {
                session.invalidate(errorMessage: "Connection failed. Please try again.")
                return
            }

            // Extract tag identifier based on tag type
            var identifier: String?

            switch tag {
            case .iso7816(let iso7816Tag):
                identifier = iso7816Tag.identifier.map { String(format: "%02hhx", $0) }.joined()

            case .feliCa(let feliCaTag):
                identifier = feliCaTag.currentIDm.map { String(format: "%02hhx", $0) }.joined()

            case .iso15693(let iso15693Tag):
                identifier = iso15693Tag.identifier.map { String(format: "%02hhx", $0) }.joined()

            case .miFare(let miFareTag):
                identifier = miFareTag.identifier.map { String(format: "%02hhx", $0) }.joined()

            @unknown default:
                session.invalidate(errorMessage: "Unsupported tag type.")
                return
            }

            guard let tagId = identifier else {
                session.invalidate(errorMessage: "Could not read tag.")
                return
            }

            // Invalidate immediately without showing alert message for faster dismissal
            session.invalidate()

            Task { @MainActor in
                self.lastScannedTag = tagId

                // Call the callback - ContentView will handle toggling if tag is registered
                self.onTagScanned?(tagId)

                self.stopScanning()
            }
        }
    }
}
