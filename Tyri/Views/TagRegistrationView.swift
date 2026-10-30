import SwiftUI

struct TagRegistrationView: View {
    @StateObject private var nfc = NFCManager.shared
    @StateObject private var config = AppConfigurationStore.shared

    var body: some View {
        Form {
            Section {
                Label(config.isTagRegistered ? "Your tag is connected" : "Connect your tag",
                      systemImage: config.isTagRegistered ? "checkmark.circle" : "sensor.tag.radiowaves.forward")
                    .font(.headline)
                Text(config.isTagRegistered
                     ? "Open Tyri and scan your tag to start or stop tag blocks."
                     : "Hold the top of your iPhone near your NFC tag after starting a scan.")
                    .foregroundStyle(.secondary)
            }
            Section {
                if config.isTagRegistered {
                    Button("Disconnect tag", role: .destructive) { config.clearTagRegistration() }
                } else if nfc.isScanning {
                    ProgressView("Looking for your tag…")
                    Button("Cancel scan") { nfc.stopScanning() }
                } else {
                    Button { nfc.startScanning() } label: {
                        Label("Scan tag", systemImage: "sensor.tag.radiowaves.forward").frame(maxWidth: .infinity)
                    }
                    .primaryActionButton()
                    .listRowBackground(Color.clear)
                }
            }
            if let error = nfc.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            }
        }
        .navigationTitle("NFC tag")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { nfc.stopScanning() }
    }
}
