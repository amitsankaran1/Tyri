//
//  TypingChallengeView.swift
//  Tyri
//
//  Created by Amit Sankaran on 1/12/26.
//

import SwiftUI

struct TypingChallengeView: View {
    @Binding var isPresented: Bool
    @StateObject private var screenTimeManager = ScreenTimeManager.shared

    @State private var userInput = ""
    @State private var isCorrect = false
    @State private var showError = false

    private let challengeText = """
I am choosing to use my time wisely. These apps distract me from my goals and waste my potential. I will stay focused on what matters most to me.
"""


    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Type the passage below to clear current blocks without your tag.")
                        .foregroundStyle(.secondary)
                }
                Section("Passage") { Text(challengeText) }
                Section {
                    TextEditor(text: $userInput).frame(minHeight: 160)
                        .accessibilityLabel("Type the passage")
                        .onChange(of: userInput) { _ in showError = false; checkIfCorrect() }
                } header: { Text("Your response") } footer: {
                    if isCorrect { Label("Passage matches", systemImage: "checkmark.circle") }
                    else if showError { Text("The passage doesn't match yet.") }
                    else { Text("Capitalization and extra spaces don't need to match.") }
                }
                Section {
                    Button { attemptSubmit() } label: { Text("Disable blocking").frame(maxWidth: .infinity) }
                        .primaryActionButton().disabled(!isCorrect).listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Emergency Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            }
        }
    }

    private func checkIfCorrect() {
        // Allow small differences (case insensitive, ignore extra whitespace)
        let normalizedChallenge = challengeText.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let normalizedInput = userInput.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        isCorrect = normalizedInput == normalizedChallenge
    }

    private func attemptSubmit() {
        checkIfCorrect()

        if isCorrect {
            // Emergency override — clear every active block.
            screenTimeManager.disableAllBlocks()
            isPresented = false
        } else {
            showError = true
        }
    }
}
