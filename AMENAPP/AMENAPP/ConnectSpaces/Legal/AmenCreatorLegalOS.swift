// AmenCreatorLegalOS.swift
// AMEN ConnectSpaces — Legal
//
// In-app legal document viewer with scroll-to-accept gate.
// Glass rule: chrome bar uses .ultraThinMaterial; document body is matte.
// Written: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - Main View

struct AmenCreatorLegalOS: View {
    let documentType: AmenLegalDocumentType
    let userId: String
    let requiresAcceptance: Bool
    let onAccepted: (() -> Void)?
    let onDismiss: () -> Void

    @State private var hasScrolledToBottom: Bool = false
    @State private var hasAgreed: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                documentScrollView
                if requiresAcceptance {
                    acceptanceFooter
                }
            }
        }
        .navigationTitle(documentType.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !requiresAcceptance {
                    Button("Done") {
                        onDismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityLabel("Done reading \(documentType.displayTitle)")
                }
            }
        }
    }

    // MARK: - Header Bar (chrome)

    private var headerBar: some View {
        VStack(spacing: 2) {
            Text("Version \(documentType.version)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .kerning(0.6)
            Text("Effective \(documentType.effectiveDate)")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Divider().opacity(0.20)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Version \(documentType.version), effective \(documentType.effectiveDate)")
    }

    // MARK: - Document Scroll View (matte body)

    private var documentScrollView: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                documentBody
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, requiresAcceptance ? 20 : 40)

                // Invisible sentinel — becomes visible when the user reaches the bottom.
                // The GeometryReader detects its position in the scroll view's coordinate space.
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            guard !hasScrolledToBottom else { return }
                            hasScrolledToBottom = true
                        }
                        .onChange(of: geo.frame(in: .global).minY) { _, newY in
                            guard !hasScrolledToBottom else { return }
                            if newY > 0 {
                                hasScrolledToBottom = true
                            }
                        }
                }
                .frame(height: 1)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Document Body

    @ViewBuilder
    private var documentBody: some View {
        let fullText = AmenLegalDocumentContent.content(for: documentType)

        if documentType == .communityStandards {
            communityStandardsBody(fullText: fullText)
        } else {
            Text(fullText)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(documentType.displayTitle + " legal text")
        }
    }

    /// Community Standards gets gold-highlighted Scripture note inline.
    @ViewBuilder
    private func communityStandardsBody(fullText: String) -> some View {
        let paragraphs = fullText.components(separatedBy: "\n\n")
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                if paragraph.hasPrefix("Scripture References") || paragraph.hasPrefix("SCRIPTURE REFERENCES") {
                    // Gold-tinted block for the Scripture attribution section
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "D9A441"))
                            .frame(width: 3)
                            .accessibilityHidden(true)
                        Text(paragraph)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "D9A441").opacity(0.90))
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(paragraph)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityLabel("Community Standards legal text")
    }

    // MARK: - Acceptance Footer

    private var acceptanceFooter: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.20)

            VStack(spacing: 14) {
                agreementToggleRow
                if let error = submissionError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
                acceptButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }

    private var agreementToggleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: $hasAgreed) {
                EmptyView()
            }
            .toggleStyle(AmenCheckToggleStyle())
            .disabled(!hasScrolledToBottom)
            .opacity(hasScrolledToBottom ? 1.0 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast), value: hasScrolledToBottom)
            .accessibilityHint(hasScrolledToBottom ? "" : "Scroll to the bottom to enable")

            Text("I have read and agree to the \(documentType.displayTitle)")
                .font(.system(size: 13))
                .foregroundStyle(hasScrolledToBottom ? Color.white.opacity(0.80) : Color.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
                .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast), value: hasScrolledToBottom)
                .accessibilityHidden(true)   // combined with Toggle above
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agreement toggle: I have read and agree to the \(documentType.displayTitle)")
        .accessibilityAddTraits(hasAgreed ? [.isSelected] : [])
        .accessibilityHint(hasScrolledToBottom ? "Toggle to agree" : "Scroll to the bottom to enable")
    }

    private var acceptButton: some View {
        let isEnabled = hasScrolledToBottom && hasAgreed && !isSubmitting

        return Button(action: submitAcceptance) {
            Group {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(hex: "070607"))
                } else {
                    Text("Accept and Continue")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isEnabled ? Color(hex: "D9A441") : Color(hex: "D9A441").opacity(0.30))
        )
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.4)
        .animation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast), value: isEnabled)
        .accessibilityLabel("Accept and Continue")
        .accessibilityHint(isEnabled ? "" : "Scroll to the bottom to enable")
    }

    // MARK: - Submit Acceptance

    private func submitAcceptance() {
        guard hasScrolledToBottom, hasAgreed, !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil

        Task {
            do {
                let callable = Functions.functions().httpsCallable("recordLegalAcceptance")
                let payload: [String: Any] = [
                    "documentType": documentType.rawValue,
                    "version": documentType.version,
                    "userId": userId
                ]
                _ = try await callable.call(payload)
                await MainActor.run {
                    isSubmitting = false
                    onAccepted?()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "Could not record acceptance. Please try again."
                }
            }
        }
    }
}

// MARK: - Custom Check Toggle Style

private struct AmenCheckToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isOn ? Color(hex: "D9A441") : Color.white.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                configuration.isOn ? Color(hex: "D9A441") : Color.white.opacity(0.25),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: 22, height: 22)

                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Color(hex: "070607"))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        AmenCreatorLegalOS(
            documentType: .creatorAgreement,
            userId: "preview-user-1",
            requiresAcceptance: true,
            onAccepted: {},
            onDismiss: {}
        )
    }
    .preferredColorScheme(.dark)
}
#endif
