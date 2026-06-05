// PrePublishSafetyGate.swift
// AMENAPP — SafetyOS
// View modifier + gate view that intercepts publish/share actions to run safety scan.
// Sensitive content defaults to the most restricted audience — never auto-escalates.

import SwiftUI

// MARK: - Gate View

struct PrePublishSafetyGate: View {
    let card: ContentCard
    let postBody: String
    let safetyService: any SafetyService
    let onClear: () -> Void      // No flags — proceed
    let onFlagged: ([SafetyFlag]) -> Void  // Flags found — user must review
    let onCancel: () -> Void

    @State private var scanning = false
    @State private var flags: [SafetyFlag] = []
    @State private var scanComplete = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            if scanning {
                scanningView
            } else if scanComplete {
                if flags.isEmpty {
                    clearView
                } else {
                    flaggedView
                }
            }
        }
        .padding(20)
        .task { await runScan() }
    }

    // MARK: - States

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Running privacy & safety check…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private var clearView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.green)
            Text("Looks Good")
                .font(.headline)
            Text("No privacy concerns detected. You're good to share.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onClear()
            } label: {
                Text("Continue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.amenGold, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var flaggedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Privacy Flags Detected")
                    .font(.headline)
            }

            Text("We noticed some content that may need your attention before sharing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(flags, id: \.rawValue) { flag in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.orange)
                        Text(flagDescription(flag))
                            .font(.subheadline)
                    }
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            // Defaulted-to-restricted note
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("Audience has been set to your most restricted option. You can change it in the review step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button {
                    onFlagged(flags)
                } label: {
                    Text("Review & Continue")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Logic

    private func runScan() async {
        scanning = true
        flags = await safetyService.scan(card, body: postBody)
        scanning = false
        scanComplete = true
        if flags.isEmpty {
            // Auto-proceed on clear scan after a brief moment
            try? await Task.sleep(nanoseconds: 800_000_000)
            onClear()
        }
    }

    private func flagDescription(_ flag: SafetyFlag) -> String {
        switch flag {
        case .minorPresent:      return "This content may identify a minor."
        case .schoolIdentifier:  return "A school name or identifier was detected."
        case .homeAddress:       return "A home address or location was detected."
        case .phoneNumber:       return "A phone number was detected."
        case .privatePrayer:     return "This contains a private prayer request."
        case .medical:           return "Medical information was detected."
        case .financial:         return "Financial information was detected."
        case .churchInternal:    return "This was marked as church-internal."
        case .paidContent:       return "This is paid content that cannot be reposted freely."
        case .copyright:         return "Potential copyright content detected."
        case .crisisLanguage:    return "This content may indicate a crisis situation."
        }
    }
}
