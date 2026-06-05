// CameraIntentPickerView.swift
// AMENAPP — Camera OS
// "What are you creating?" — intent selection before capture.
// Faith intents sit alongside universal intents, not in a separate section.
//
// Design: Liquid Glass on dark/black camera context.
//   Pre-iOS 26: .ultraThinMaterial + strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
//   iOS 26+:    .glassEffect() on controls

import SwiftUI

// MARK: - CameraIntentPickerView

struct CameraIntentPickerView: View {

    // MARK: Props

    var onIntentSelected: (CameraIntent) -> Void
    var onDismiss: () -> Void

    @State private var selectedIntent: CameraIntent? = nil

    // MARK: Layout constants

    private let tileSize: CGFloat = 90
    private let tileSpacing: CGFloat = 10
    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let amberGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Sheet content
            VStack(spacing: 0) {
                headerSection
                    .padding(.top, 28)
                    .padding(.horizontal, 20)

                intentGrid
                    .padding(.top, 20)
                    .padding(.horizontal, 16)

                ctaButton
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.92).ignoresSafeArea())

            // Dismiss button — top-right
            dismissButton
                .padding(.top, 16)
                .padding(.trailing, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.black.opacity(0.88))
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What are you creating?")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text("Your intent shapes the capture, safety, and destination.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // leave space for dismiss button at top-right (44 pt wide)
        .padding(.trailing, 44)
    }

    // MARK: - Intent Grid

    private var intentGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: tileSpacing) {
                ForEach(CameraIntent.allCases) { intent in
                    CameraIntentTile(
                        intent: intent,
                        isSelected: selectedIntent == intent
                    ) {
                        withAnimation(
                            reduceMotion
                                ? .easeOut(duration: 0.15)
                                : .spring(response: 0.25, dampingFraction: 0.78)
                        ) {
                            selectedIntent = (selectedIntent == intent) ? nil : intent
                        }
                    }
                    .frame(width: tileSize, height: tileSize)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Intent options")
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            guard let intent = selectedIntent else { return }
            onIntentSelected(intent)
        } label: {
            Text("Start Capturing")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selectedIntent == nil ? Color.black.opacity(0.45) : Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(
                            selectedIntent == nil
                                ? Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.35)
                                : Color(red: 1.0, green: 0.84, blue: 0.0)
                        )
                )
        }
        .disabled(selectedIntent == nil)
        .accessibilityLabel(
            selectedIntent.map { "Start capturing \($0.displayName)" }
                ?? "Start capturing, select an intent first"
        )
        .accessibilityHint(selectedIntent == nil ? "Tap an intent above to enable this button" : "")
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(dismissButtonBackground)
        }
        .accessibilityLabel("Dismiss")
    }

    @ViewBuilder
    private var dismissButtonBackground: some View {
        if #available(iOS 26, *) {
            Circle().glassEffect()
        } else {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }
}

// MARK: - CameraIntentTile

private struct CameraIntentTile: View {

    let intent: CameraIntent
    let isSelected: Bool
    let onTap: () -> Void

    private let amberGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                // Tile background
                tileBackground

                // Content
                VStack(spacing: 6) {
                    Image(systemName: intent.systemIcon)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(.white)

                    Text(intent.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)

                // Faith intent indicator — small cross at top-right
                if intent.isFaithIntent {
                    Image(systemName: "cross.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(6)
                        .accessibilityHidden(true)
                }

                // Selected amber overlay
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(amberGold.opacity(0.25))
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(intent.displayName)
        .accessibilityHint(isSelected ? "" : "Tap to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Tile background

    @ViewBuilder
    private var tileBackground: some View {
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(
                    isSelected
                        ? .regular.tint(Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.18))
                        : .regular,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
            }
        }
    }
}

// MARK: - Preview

#Preview("Camera Intent Picker") {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            CameraIntentPickerView(
                onIntentSelected: { intent in
                    print("Selected intent: \(intent.displayName)")
                },
                onDismiss: {
                    print("Dismissed")
                }
            )
        }
}
