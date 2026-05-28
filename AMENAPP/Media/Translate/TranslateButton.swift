// TranslateButton.swift
// AMENAPP — Media/Translate
//
// Globe button that calls the "translateText" Firebase callable and
// flips the caption text with a rotation3DEffect animation.

import SwiftUI
import FirebaseFunctions

// MARK: - TranslateButton

@MainActor
struct TranslateButton: View {
    var originalText: String
    @Binding var translatedText: String?
    var targetLocale: String = Locale.current.identifier

    // MARK: State

    @State private var isLoading = false
    @State private var showErrorToast = false
    @State private var errorMessage = ""
    @State private var isFlipped = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Body

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(Color.amenGold)
                    .frame(width: 28, height: 28)
            } else {
                Button {
                    Task { await translate() }
                } label: {
                    Image(systemName: globeIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(translatedText != nil ? Color.amenGold : AmenTheme.Colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(translatedText != nil ? "Show original text" : "Translate text")
            }
        }
        .overlay(alignment: .bottom) {
            if showErrorToast {
                errorToast
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
                    .offset(y: 30)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82), value: isLoading)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18), value: showErrorToast)
    }

    // MARK: Subviews

    private var globeIcon: String {
        // Alternate between hemisphere icons for visual interest
        translatedText != nil ? "globe.europe.africa.fill" : "globe.americas"
    }

    private var errorToast: some View {
        Text(errorMessage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(0.88))
            }
            .frame(maxWidth: 180)
    }

    // MARK: Translation Action

    private func translate() async {
        // Toggle back to original if already translated
        if translatedText != nil {
            withAnimation(flipAnimation) {
                translatedText = nil
                isFlipped = false
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let functions = Functions.functions()
            let callable = functions.httpsCallable("translateText")
            let payload: [String: Any] = [
                "text": originalText,
                "targetLocale": targetLocale
            ]
            let result = try await callable.call(payload)

            guard let dict = result.data as? [String: Any],
                  let translated = dict["translatedText"] as? String else {
                throw NSError(domain: "TranslateButton", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"])
            }

            withAnimation(flipAnimation) {
                translatedText = translated
                isFlipped = true
            }
        } catch {
            showError("Translation unavailable. Please try again.")
        }
    }

    private var flipAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: LiquidGlassTokens.motionFast)
        }
        return .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.80)
    }

    private func showError(_ message: String) {
        errorMessage = message
        withAnimation { showErrorToast = true }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { showErrorToast = false }
        }
    }
}

// MARK: - CaptionFlipView

/// Wraps a caption string that flips vertically when `isFlipped` changes.
/// Use this to animate between `originalText` and `translatedText`.
@MainActor
struct CaptionFlipView: View {
    var originalText: String
    var translatedText: String?
    @Binding var isShowingTranslation: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var displayText: String {
        isShowingTranslation ? (translatedText ?? originalText) : originalText
    }

    var body: some View {
        Text(displayText)
            .font(.body)
            .foregroundStyle(AmenTheme.Colors.textPrimary)
            .rotation3DEffect(
                .degrees(isShowingTranslation && !reduceMotion ? 0 : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .animation(
                reduceMotion
                    ? .easeOut(duration: LiquidGlassTokens.motionFast)
                    : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.80),
                value: isShowingTranslation
            )
            .id(displayText) // Force re-render on text change
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .rotation3D(angle: .degrees(-90), axis: (1, 0, 0))),
                        removal:   .opacity.combined(with: .rotation3D(angle: .degrees(90), axis: (1, 0, 0)))
                    )
            )
    }
}

// MARK: - AnyTransition+rotation3D helper

private extension AnyTransition {
    static func rotation3D(angle: Angle, axis: (Double, Double, Double)) -> AnyTransition {
        let a = (x: CGFloat(axis.0), y: CGFloat(axis.1), z: CGFloat(axis.2))
        return .modifier(
            active: Rotation3DModifier(angle: angle, axis: a, opacity: 0),
            identity: Rotation3DModifier(angle: .zero, axis: a, opacity: 1)
        )
    }
}

private struct Rotation3DModifier: ViewModifier {
    var angle: Angle
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat)
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(angle, axis: axis)
            .opacity(opacity)
    }
}
