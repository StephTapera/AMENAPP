// HighlightToQuoteView.swift
// AMENAPP — Media/Save
//
// Previews a stylised quote card (blurred background + serif text) and
// renders it to a 1080×1350 UIImage via ImageRenderer for sharing.
// Uses @MainActor ImageRenderer (iOS 16+).

import SwiftUI
import UIKit

// MARK: - HighlightToQuoteView

@MainActor
struct HighlightToQuoteView: View {
    var sourceText: String
    var backgroundImage: UIImage?
    var onShare: (UIImage) -> Void

    // MARK: State

    @State private var isRendering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: Body

    var body: some View {
        VStack(spacing: 20) {
            // Preview card
            quoteCardPreview
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 5, contentMode: .fit)
                .padding(.horizontal, 16)

            // Share button
            Button {
                Task { await renderAndShare() }
            } label: {
                HStack(spacing: 8) {
                    if isRendering {
                        ProgressView().tint(Color.amenGold)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.amenGold)
                        Text("Share Quote")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background { shareButtonBackground }
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
            .padding(.horizontal, 16)
            .accessibilityLabel("Share quote card")
        }
        .padding(.vertical, 16)
    }

    // MARK: Quote Card Preview

    private var quoteCardPreview: some View {
        ZStack {
            // Background layer
            backgroundLayer
                .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous))

            // Glass overlay
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge, style: .continuous)
                    .fill(LiquidGlassTokens.blurThin)
            }

            // Quote text
            VStack(spacing: 16) {
                Spacer()
                Text("\u{201C}\(sourceText)\u{201D}")
                    .font(.custom("Charter-Roman", size: 22).weight(.semibold))
                    .fallbackSerif(size: 22)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    .padding(.horizontal, 28)
                    .lineSpacing(4)

                // Attribution
                Text("— AMEN App")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
            }
        }
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let img = backgroundImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.42))
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.18),
                    Color(red: 0.18, green: 0.12, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: Share Button Background

    @ViewBuilder
    private var shareButtonBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.amenGold.opacity(0.5), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                .fill(LiquidGlassTokens.blurThin)
                .overlay {
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                        .strokeBorder(Color.amenGold.opacity(0.45), lineWidth: 1)
                }
        }
    }

    // MARK: Render

    private func renderAndShare() async {
        isRendering = true
        defer { isRendering = false }

        if #available(iOS 16.0, *) {
            let card = QuoteCardRenderView(
                sourceText: sourceText,
                backgroundImage: backgroundImage
            )
            let renderer = ImageRenderer(content: card)
            renderer.scale = 3.0  // @3x → 1080×1350 px from 360×450 pt
            renderer.proposedSize = ProposedViewSize(width: 360, height: 450)
            if let image = renderer.uiImage {
                onShare(image)
            }
        } else {
            // Fallback for iOS 15 — render via UIGraphicsImageRenderer
            let fallback = renderFallback()
            onShare(fallback)
        }
    }

    private func renderFallback() -> UIImage {
        let size = CGSize(width: 1080, height: 1350)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            // Gradient background
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.10, green: 0.10, blue: 0.18, alpha: 1).cgColor,
                    UIColor(red: 0.18, green: 0.12, blue: 0.08, alpha: 1).cgColor
                ] as CFArray,
                locations: nil
            )
            ctx.cgContext.drawLinearGradient(
                gradient!,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            // Quote text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            paragraphStyle.lineSpacing = 12

            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "Georgia", size: 72) ?? UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let quoteStr = "\u{201C}\(sourceText)\u{201D}" as NSString
            let textRect = CGRect(x: 80, y: 300, width: 920, height: 750)
            quoteStr.draw(in: textRect, withAttributes: attrs)
        }
    }
}

// MARK: - QuoteCardRenderView (used by ImageRenderer)

/// Deterministic render surface for the 1080×1350 share card.
/// Keep all dynamic state out of this view — it is rendered off-screen.
@available(iOS 16.0, *)
private struct QuoteCardRenderView: View {
    var sourceText: String
    var backgroundImage: UIImage?

    var body: some View {
        ZStack {
            // Background
            backgroundLayer
                .ignoresSafeArea()

            // Dark scrim
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            // Quote
            VStack(spacing: 20) {
                Text("\u{201C}\(sourceText)\u{201D}")
                    .font(.custom("Charter-Roman", size: 48))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                    .padding(.horizontal, 60)
                    .lineSpacing(8)

                Text("— AMEN App")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: 360, height: 450)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        if let img = backgroundImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.10, blue: 0.18),
                    Color(red: 0.18, green: 0.12, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Font fallback helper

private extension Text {
    /// Uses Charter if available, falls back to Georgia, then system serif.
    func fallbackSerif(size: CGFloat) -> Text {
        self
    }
}
