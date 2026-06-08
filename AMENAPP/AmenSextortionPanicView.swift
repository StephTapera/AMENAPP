// AmenSextortionPanicView.swift
// AMENAPP
// Emergency panic-mode sheet for sextortion/image-based-abuse victims.
// Locks DMs, escalates to trusted contacts, surfaces crisis resources.

import SwiftUI
import FirebaseAuth

struct SextortionPanicFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .confirm
    @State private var isActivating = false
    @State private var activated = false
    @State private var errorMessage: String?

    enum Step { case confirm, activating, done }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .confirm: confirmStep
                case .activating: activatingStep
                case .done: doneStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .confirm {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: Confirm

    private var confirmStep: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "shield.lefthalf.filled.slash")
                .font(.systemScaled(52))
                .foregroundStyle(.red)

            VStack(spacing: 10) {
                Text("Get Immediate Help")
                    .font(.title2.bold())
                Text("Activating Panic Mode will:\n\u{2022} Lock your DMs from unknown contacts\n\u{2022} Alert your trusted contacts\n\u{2022} Connect you with crisis resources")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                Button(role: .destructive) {
                    activatePanicMode()
                } label: {
                    Text("Activate Panic Mode")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Link("Call or Text 988 (Crisis Lifeline)", destination: URL(string: "tel:988")!)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    // MARK: Activating

    private var activatingStep: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
            Text("Activating safety mode\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Done

    private var doneStep: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.systemScaled(52))
                .foregroundStyle(.green)

            VStack(spacing: 10) {
                Text("You're Protected")
                    .font(.title2.bold())
                Text("Your DMs are locked and your trusted contacts have been notified. If you need to talk to someone, Selah's crisis support is always available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button("Done") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(.horizontal, 28)

            Spacer()
        }
    }

    // MARK: Action

    private func activatePanicMode() {
        guard let uid = try? currentUserId() else { return }
        step = .activating
        Task {
            do {
                try await AmenSocialSafetyService.shared.activateSextortionPanicFlow(for: uid)
                step = .done
            } catch {
                errorMessage = error.localizedDescription
                step = .confirm
            }
        }
    }

    private func currentUserId() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: 0)
        }
        return uid
    }
}
