// VoicePrayerSafetyGateView.swift
// AMEN App — Voice Prayer & Testimony Comments
//
// Pre-record safety gate. Shown before any microphone access is requested.
// Uses Liquid Glass capsule buttons for actions.
// Supports Reduce Motion, Dynamic Type, VoiceOver, and Reduce Transparency.

import SwiftUI

struct VoicePrayerSafetyGateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let availableTypes: [VoiceCommentType]
    let onSelect: (VoiceCommentType) -> Void
    let onUseTextInstead: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color(uiColor: .separator))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 24) {
                    // Header icon
                    ZStack {
                        Circle()
                            .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.thinMaterial))
                            .frame(width: 72, height: 72)
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                    .scaleEffect(appeared ? 1.0 : 0.7)
                    .opacity(appeared ? 1.0 : 0.0)
                    .accessibilityHidden(true)

                    // Title
                    VStack(spacing: 8) {
                        Text("Voice Prayer & Testimony")
                            .font(.systemScaled(20, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                            .multilineTextAlignment(.center)

                        Text("Voice notes in AMEN are for prayers and testimonies only — not general comments.")
                            .font(.systemScaled(15))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Safety notice
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Please do not share:", systemImage: "exclamationmark.shield.fill")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(safetyItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "minus")
                                        .font(.systemScaled(11, weight: .bold))
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                        .padding(.top, 3)
                                    Text(item)
                                        .font(.systemScaled(13))
                                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(reduceTransparency
                                  ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                                  : AnyShapeStyle(.regularMaterial))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )

                    // Type selection buttons (Liquid Glass)
                    VStack(spacing: 12) {
                        ForEach(availableTypes, id: \.self) { type in
                            Button {
                                HapticManager.impact(style: .medium)
                                dismiss()
                                onSelect(type)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: type.systemIcon)
                                        .font(.systemScaled(16, weight: .semibold))
                                    Text(type.commentType == .prayer ? "Start Prayer" : "Start Testimony")
                                        .font(.systemScaled(16, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.systemScaled(13, weight: .semibold))
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }
                                .foregroundStyle(Color(uiColor: .label))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(reduceTransparency
                                              ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                                              : AnyShapeStyle(.regularMaterial))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(type == .prayer ? "Start Prayer recording" : "Start Testimony recording")
                        }
                    }

                    // Use Text Instead
                    Button {
                        HapticManager.impact(style: .light)
                        dismiss()
                        onUseTextInstead()
                    } label: {
                        Text("Use Text Instead")
                            .font(.systemScaled(15, weight: .medium))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use text comment instead")

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            withAnimation(reduceMotion
                          ? .easeOut(duration: 0.1)
                          : .spring(response: 0.45, dampingFraction: 0.72)) {
                appeared = true
            }
        }
    }

    private let safetyItems = [
        "Private medical or health information",
        "Financial details or account information",
        "Explicit, hateful, or threatening content",
        "Names or identifying details of others without consent",
        "Content unrelated to prayer or testimony"
    ]
}

// MARK: - Convenience extension

private extension VoiceCommentType {
    var commentType: VoiceCommentType { self }
}
