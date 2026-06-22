// CommentCrisisHandlerView.swift
// AMENAPP — Smart Comments Wave 2
//
// Shown PRIVATELY to the AUTHOR of a comment that triggered a crisis signal.
// NOT shown to other readers. The comment IS still posted (crisis handling rule:
// do not block; show resources to the author privately).
//
// SAFETY INVARIANTS:
//   - NEVER surface method content
//   - NEVER tell the author "your comment was flagged as dangerous"
//   - NEVER show this to anyone other than the author
//   - The comment remains posted (this is purely additive; author sees resources)
//
// Design: warm amber/gold tones; NOT red or alarming; non-judgmental.
//
// Usage:
//   CommentCrisisHandlerView(category: .selfHarm)
//       .sheet(isPresented: $showCrisisHandler) { ... }

import SwiftUI
import Foundation

struct CommentCrisisHandlerView: View {

    /// The crisis category that was detected. Must be .selfHarm or .childSafety.
    let category: ModerationCategory

    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            crisisBackground

            ScrollView {
                VStack(spacing: 0) {
                    warmHeaderIcon
                        .padding(.top, 32)

                    messageSection
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    resourcesCard
                        .padding(.top, 24)
                        .padding(.horizontal, 20)

                    postedConfirmation
                        .padding(.top, 20)
                        .padding(.horizontal, 24)

                    dismissButton
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                        .padding(.horizontal, 24)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    // MARK: - Warm Header Icon

    private var warmHeaderIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.30),
                            Color(red: 1.0, green: 0.70, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 68, height: 68)
                .shadow(color: Color(red: 1.0, green: 0.70, blue: 0.10).opacity(0.35), radius: 12, x: 0, y: 4)

            Image(systemName: "heart.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Message Section

    private var messageSection: some View {
        VStack(spacing: 12) {
            Text("You're not alone")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 0.50, green: 0.32, blue: 0.00))
                .multilineTextAlignment(.center)

            Text("We noticed your message may reflect something difficult you're going through. Whatever you're facing, there are people who care and want to help.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(red: 0.45, green: 0.28, blue: 0.00).opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    // MARK: - Resources Card

    private var resourcesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Free, confidential support")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.00))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()
                .background(Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.5))

            resourceRow(
                icon: "message.fill",
                title: "Crisis Text Line",
                detail: "Text HOME to 741741",
                accessibilityHint: "Text HOME to 741741 to reach a crisis counselor",
                action: { openURL(URL(string: "sms:741741&body=HOME")!) }
            )

            Divider()
                .background(Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.5))
                .padding(.leading, 56)

            resourceRow(
                icon: "phone.fill",
                title: "988 Suicide & Crisis Lifeline",
                detail: "Call or text 988 — free, 24/7",
                accessibilityHint: "Call or text 988 to reach the national crisis lifeline",
                action: { openURL(URL(string: "tel:988")!) }
            )

            Divider()
                .background(Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.5))
                .padding(.leading, 56)

            resourceRow(
                icon: "cross.fill",
                title: "Hope for the Heart",
                detail: "hopeforthe heart.org · 1-800-488-HOPE",
                accessibilityHint: "Visit Hope for the Heart at hopeforthe heart.org",
                action: { openURL(URL(string: "https://www.hopefortheheart.org")!) }
            )

            Spacer().frame(height: 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(reduceTransparency
                    ? Color(red: 1.0, green: 0.96, blue: 0.85)
                    : Color(red: 1.0, green: 0.93, blue: 0.70).opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color(red: 1.0, green: 0.80, blue: 0.30).opacity(0.4), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func resourceRow(
        icon: String,
        title: String,
        detail: String,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.30).opacity(0.4))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.60, green: 0.38, blue: 0.00))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.45, green: 0.28, blue: 0.00))
                    Text(detail)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(red: 0.50, green: 0.32, blue: 0.00).opacity(0.75))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.45, blue: 0.00).opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Posted Confirmation

    /// Non-alarming reassurance that the comment was shared normally.
    private var postedConfirmation: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color(red: 0.45, green: 0.60, blue: 0.20))
            Text("Your post was shared with the community.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Your post was shared with the community")
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button(action: {
            onDismiss?()
            dismiss()
        }) {
            Text("I'm okay for now")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.50, green: 0.32, blue: 0.00))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            reduceTransparency
                                ? Color(red: 1.0, green: 0.88, blue: 0.50)
                                : Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.65)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color(red: 1.0, green: 0.75, blue: 0.20).opacity(0.55), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }

    // MARK: - Crisis Background

    @ViewBuilder
    private var crisisBackground: some View {
        if reduceTransparency {
            Color(red: 1.0, green: 0.97, blue: 0.88)
                .ignoresSafeArea()
        } else {
            ZStack {
                Color(red: 1.0, green: 0.96, blue: 0.82).opacity(0.92)
                    .ignoresSafeArea()
                // Soft radial warmth at top center
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.88, blue: 0.40).opacity(0.28),
                        Color.clear
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 280
                )
                .ignoresSafeArea()
            }
        }
    }
}
