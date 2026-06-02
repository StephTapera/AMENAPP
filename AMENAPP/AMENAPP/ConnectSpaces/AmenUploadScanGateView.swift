// AmenUploadScanGateView.swift
// AMEN Connect + Spaces — Pre-Upload Safety Gate
// Agent 8 — built 2026-06-01
//
// Hard safety rule enforced:
//   childSafetyScanBlocksBeforePublish (AmenConnectSpacesHardSafetyRule)
//
// When decision.canContinue == false, the ONLY forward path is "Remove this
// content".  There is no dismiss, no "Upload anyway", and no override button.
// This is a non-negotiable product constraint.

import SwiftUI

struct AmenUploadScanGateView: View {

    let uploadRef: String
    let surface: AmenConnectSpacesSurface
    let onApproved: () -> Void
    let onBlocked: () -> Void

    @State private var scanState: ScanState = .scanning
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State machine

    private enum ScanState {
        case scanning
        case approved(AmenConnectSpacesAegisGateDecision)
        case blocked(AmenConnectSpacesAegisGateDecision)
        case failed(String)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Matte background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            switch scanState {
            case .scanning:
                scanningCard

            case .approved:
                approvedCard

            case .blocked(let decision):
                blockedCard(decision)

            case .failed(let message):
                // Treat scan failure as blocked for child safety — never let
                // an infrastructure error open the gate.
                failedCard(message)
            }
        }
        .task {
            await runScan()
        }
    }

    // MARK: - Scanning card

    private var scanningCard: some View {
        matteCard {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(Color(red: 0.851, green: 0.643, blue: 0.255)) // amenGold
                    .accessibilityLabel("Scanning in progress")

                Text("Checking upload for family safety\u{2026}")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking upload for family safety")
    }

    // MARK: - Approved card

    private var approvedCard: some View {
        matteCard {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.green)
                    .accessibilityHidden(true)

                Text("Upload cleared")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Upload cleared for family safety")
    }

    // MARK: - Blocked card

    private func blockedCard(_ decision: AmenConnectSpacesAegisGateDecision) -> some View {
        matteCard {
            VStack(alignment: .leading, spacing: 18) {
                // Error header
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.red)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload blocked")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Possible child safety concern detected.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Upload blocked — possible child safety concern detected")

                // Flag list
                if !decision.flags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected signals:")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(decision.flags) { flag in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.red.opacity(0.7))
                                    .frame(width: 7, height: 7)
                                    .accessibilityHidden(true)

                                Text(flagDisplayLabel(flag))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(flagDisplayLabel(flag))
                        }
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.red.opacity(0.07))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                            }
                    }
                }

                // Action buttons
                // Hard rule: NO dismiss, NO "Upload anyway"
                VStack(spacing: 10) {
                    Button {
                        onBlocked()
                    } label: {
                        Text("Remove this content")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(red: 0.851, green: 0.643, blue: 0.255)) // amenGold
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this content")

                    Button {
                        // Stub navigation — wave D implementation
                    } label: {
                        Text("Contact support")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Contact support")
                }
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: - Failed card (treat as blocked per child safety rule)

    private func failedCard(_ message: String) -> some View {
        matteCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.red)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload blocked")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("Safety scan could not be completed.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Upload blocked — safety scan could not be completed")

                VStack(spacing: 10) {
                    Button {
                        onBlocked()
                    } label: {
                        Text("Remove this content")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(red: 0.851, green: 0.643, blue: 0.255)) // amenGold
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this content")

                    Button {
                        // Stub navigation — wave D implementation
                    } label: {
                        Text("Contact support")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Contact support")
                }
            }
            .padding(.vertical, 24)
        }
    }

    // MARK: - Matte card container

    @ViewBuilder
    private func matteCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            content()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: 380)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
        .padding(.horizontal, 24)
    }

    // MARK: - Flag label helper

    private func flagDisplayLabel(_ flag: AmenConnectSpacesAegisFlag) -> String {
        switch flag.capabilityRef {
        case "C45": return "C45 — Child face detected"
        case "C46": return "C46 — Minor in frame"
        case "C47": return "C47 — Child safety policy violation"
        default:    return "\(flag.capabilityRef) — Safety signal detected"
        }
    }

    // MARK: - Scan task

    private func runScan() async {
        do {
            let decision = try await AmenConnectSpacesAegisService.shared.scanUpload(
                uploadRef: uploadRef,
                surface: surface
            )
            if decision.canContinue {
                scanState = .approved(decision)
                // Dismiss after a brief matte success display.
                let delay: UInt64 = reduceMotion ? 0 : 1_500_000_000
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                onApproved()
            } else {
                scanState = .blocked(decision)
                // Hard rule: childSafetyScanBlocksBeforePublish
                // No auto-dismiss, no override. User must tap "Remove this content".
            }
        } catch {
            // Scan failure is treated as blocked — never let an infrastructure
            // error open the child-safety gate.
            scanState = .failed(error.localizedDescription)
        }
    }
}
