import SwiftUI
import FirebaseFirestore

struct AlgoliaMentionSuggestionRow: View {
    let user: AlgoliaUser
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    // Fallback profile image URL fetched from Firestore when Algolia index lacks it
    @State private var resolvedImageURL: String? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // ── Avatar ─────────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .frame(width: 40, height: 40)

                    let effectiveURL = resolvedImageURL ?? user.profileImageURL

                    if let urlStr = effectiveURL,
                       !urlStr.isEmpty,
                       let url = URL(string: urlStr) {
                        CachedAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } placeholder: {
                            Text(user.displayName.prefix(1).uppercased())
                                .font(AMENFont.bold(16))
                                .foregroundStyle(.primary)
                        }
                    } else {
                        Text(user.displayName.prefix(1).uppercased())
                            .font(AMENFont.bold(16))
                            .foregroundStyle(.primary)
                    }
                }
                .task(id: user.objectID) {
                    // Only fetch from Firestore when Algolia didn't return a profile image
                    guard (user.profileImageURL ?? "").isEmpty else { return }
                    if let url = await fetchProfileImageURL(userId: user.objectID) {
                        resolvedImageURL = url
                    }
                }

                // ── Name + username ────────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    // Display name with yellow marker highlight
                    Text(user.displayName)
                        .font(AMENFont.bold(15))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(alignment: .center) {
                            AlgoliaBrushstrokeHighlight()
                                .foregroundStyle(Color(red: 1.0, green: 0.88, blue: 0.15, opacity: 0.75))
                        }

                    Text("@\(user.username)")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Subtle chevron affordance
                Image(systemName: "arrow.up.left")
                    .font(.systemScaled(11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(
                isPressed
                    ? Color(uiColor: .tertiarySystemFill)
                    : Color.clear
            )
            .animation(reduceMotion ? .none : .easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        ._onButtonGesture { pressing in
            isPressed = pressing
        } perform: {}
    }

    /// Fetches profileImageURL from Firestore when Algolia's index doesn't have it.
    private func fetchProfileImageURL(userId: String) async -> String? {
        guard !userId.isEmpty else { return nil }
        do {
            let doc = try await Firestore.firestore().collection("users").document(userId).getDocument()
            return doc.data()?["profileImageURL"] as? String
        } catch {
            return nil
        }
    }
}

// MARK: - Brushstroke highlight shape

private struct AlgoliaBrushstrokeHighlight: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Slightly irregular rounded rect that mimics a marker sweep
        p.move(to: CGPoint(x: w * 0.02, y: h * 0.55))
        p.addCurve(
            to: CGPoint(x: w * 0.98, y: h * 0.45),
            control1: CGPoint(x: w * 0.25, y: h * 0.20),
            control2: CGPoint(x: w * 0.75, y: h * 0.10)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.04, y: h * 0.95),
            control1: CGPoint(x: w * 0.80, y: h * 1.10),
            control2: CGPoint(x: w * 0.30, y: h * 1.05)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Berean Tone Popup

// MARK: - Berean Tone Popup (Liquid Glass + Sticker Label Aesthetic)
struct BereanTonePopup: View {
    let suggestion: String?
    let onUse: (String) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardScale: CGFloat = 0.88
    @State private var cardOpacity: Double = 0
    @State private var sparkleRotation: Double = -8
    @State private var usePressed = false
    @State private var keepPressed = false
    @State private var labelWiggle: Double = 0

    // Sticker label highlight color (warm yellow)
    private let stickerYellow = Color(red: 1.0, green: 0.90, blue: 0.25)
    private let stickerMint   = Color(red: 0.72, green: 0.98, blue: 0.88)
    private let stickerBlue   = Color(red: 0.72, green: 0.88, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.opacity(0.01)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // ── Main card: frosted white glass ────────────────────
                VStack(spacing: 0) {
                    // Drag pill
                    Capsule()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 36, height: 4)
                        .padding(.top, 14)
                        .padding(.bottom, 16)

                    // ── Header row ────────────────────────────────────
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            // Sticker-label title — tilted, on yellow strip
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.systemScaled(17, weight: .black))
                                    .foregroundStyle(Color(red: 0.15, green: 0.15, blue: 0.15))
                                    .rotationEffect(.degrees(sparkleRotation))
                                Text("Tone Check")
                                    .font(.custom("OpenSans-ExtraBold", size: 19))
                                    .foregroundStyle(Color(red: 0.10, green: 0.10, blue: 0.10))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(stickerYellow)
                                    .rotationEffect(.degrees(-1.2))
                            )
                            .rotationEffect(.degrees(-1.2))
                            .rotationEffect(.degrees(labelWiggle))

                            Text(suggestion != nil
                                 ? "Here's a kinder way to say this"
                                 : "Your post sounds great as-is!")
                                .font(AMENFont.regular(13))
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer()
                        // Close button
                        Button { onDismiss() } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.08))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "xmark")
                                    .font(.systemScaled(11, weight: .bold))
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // ── Suggestion area ───────────────────────────────
                    if let suggestion = suggestion {
                        VStack(alignment: .leading, spacing: 12) {
                            // Context label — plain language explanation
                            HStack(spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.systemScaled(11))
                                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.35))
                                Text("Suggested rewrite — tap \"Use this\" to replace your post")
                                    .font(AMENFont.semiBold(11))
                                    .foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.35))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(stickerMint.opacity(0.7))
                            )
                            .padding(.horizontal, 16)

                            // Suggestion text on frosted glass card
                            Text(suggestion)
                                .font(AMENFont.regular(15))
                                .foregroundStyle(Color.primary)
                                .lineSpacing(5)
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(.regularMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.7), Color.white.opacity(0.2)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        }
                                )
                                .padding(.horizontal, 16)

                            // ── Action buttons ────────────────────────
                            HStack(spacing: 10) {
                                // "Use this" — replaces the post text with the suggestion
                                Button { onUse(suggestion) } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.systemScaled(15, weight: .semibold))
                                        Text("Use this")
                                            .font(AMENFont.bold(15))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [
                                                        Color(red: 0.25, green: 0.55, blue: 1.0),
                                                        Color(red: 0.45, green: 0.72, blue: 1.0)
                                                    ],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.35), radius: 8, y: 4)
                                    )
                                    .scaleEffect(usePressed ? 0.94 : 1.0)
                                    .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: usePressed)
                                }
                                .buttonStyle(PlainButtonStyle())
                                ._onButtonGesture { pressing in usePressed = pressing } perform: {}

                                // "Keep mine" — closes popup, post unchanged
                                Button { onDismiss() } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil")
                                            .font(.systemScaled(13, weight: .semibold))
                                        Text("Keep mine")
                                            .font(AMENFont.bold(15))
                                    }
                                    .foregroundStyle(Color.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(.regularMaterial)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                            }
                                    )
                                    .scaleEffect(keepPressed ? 0.94 : 1.0)
                                    .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: keepPressed)
                                }
                                .buttonStyle(PlainButtonStyle())
                                ._onButtonGesture { pressing in keepPressed = pressing } perform: {}
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 36)
                        }
                    } else {
                        // No rewrite needed — tone is already good
                        VStack(spacing: 16) {
                            Text("✅")
                                .font(.systemScaled(40))
                            Text("Your post has a great tone!\nNo changes needed.")
                                .font(AMENFont.regular(15))
                                .foregroundStyle(Color.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                            Button { onDismiss() } label: {
                                Text("Got it")
                                    .font(AMENFont.bold(15))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.45, green: 0.72, blue: 1.0)],
                                                    startPoint: .leading, endPoint: .trailing
                                                )
                                            )
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 36)
                    }
                }
                // Liquid glass card background: bright frosted white
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .onAppear {
                    withAnimation(Motion.adaptive(.spring(response: 0.40, dampingFraction: 0.70))) {
                        cardScale = 1.0
                        cardOpacity = 1.0
                    }
                    // Sparkle rocks back and forth
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(0.3)) {
                        sparkleRotation = 8
                    }
                    // Label has a tiny playful wiggle on appear
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.4)).delay(0.45)) {
                        labelWiggle = 2
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                        withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.5))) {
                            labelWiggle = 0
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Source Label Prompt (shown when AI/pasted content detected at medium confidence)
struct SourceLabelPrompt: View {
    let onPostWithSource: (String) -> Void   // passes the source string e.g. "ChatGPT"
    let onEdit: () -> Void                    // user wants to rewrite

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cardScale: CGFloat = 0.88
    @State private var cardOpacity: Double = 0
    @State private var selectedSource: String = "ChatGPT"
    @State private var postPressed = false
    @State private var editPressed = false

    private let sourceOptions = ["ChatGPT", "External", "Other AI"]
    private let stickerOrange = Color(red: 1.0, green: 0.75, blue: 0.30)
    private let stickerBlue   = Color(red: 0.72, green: 0.88, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.opacity(0.01).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag pill
                    Capsule()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 36, height: 4)
                        .padding(.top, 14)
                        .padding(.bottom, 18)

                    // ── Header ────────────────────────────────────────
                    VStack(spacing: 8) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(stickerOrange.opacity(0.2))
                                .frame(width: 56, height: 56)
                            Text("🔍")
                                .font(.systemScaled(26))
                        }

                        // Title on orange sticker label
                        Text("Looks copy-pasted")
                            .font(.custom("OpenSans-ExtraBold", size: 18))
                            .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.08))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(stickerOrange)
                                    .rotationEffect(.degrees(-1))
                            )
                            .rotationEffect(.degrees(-1))

                        Text("AMEN values your authentic voice.\nIf this isn't fully your own writing, label it so your community knows.")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)

                    // ── Source picker ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "tag.fill")
                                .font(.systemScaled(10, weight: .bold))
                                .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.80))
                            Text("source label")
                                .font(AMENFont.bold(10))
                                .foregroundStyle(Color(red: 0.20, green: 0.40, blue: 0.80))
                                .textCase(.uppercase)
                                .kerning(0.8)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(stickerBlue)
                                .rotationEffect(.degrees(0.6))
                        )
                        .rotationEffect(.degrees(0.6))
                        .padding(.leading, 20)

                        // Pill selector
                        HStack(spacing: 8) {
                            ForEach(sourceOptions, id: \.self) { opt in
                                Button {
                                    withAnimation(Motion.adaptive(.spring(response: 0.2, dampingFraction: 0.6))) {
                                        selectedSource = opt
                                    }
                                } label: {
                                    Text(opt)
                                        .font(.custom(selectedSource == opt ? "OpenSans-Bold" : "OpenSans-Regular", size: 13))
                                        .foregroundStyle(selectedSource == opt ? .white : Color.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedSource == opt
                                                    ? Color(red: 0.25, green: 0.55, blue: 1.0)
                                                    : Color.primary.opacity(0.08))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 20)

                    // ── Preview badge ─────────────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.systemScaled(11))
                            .foregroundStyle(Color.secondary)
                        Text("Your post will show a \"via \(selectedSource)\" label")
                            .font(AMENFont.regular(12))
                            .foregroundStyle(Color.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // ── Action buttons ────────────────────────────────
                    VStack(spacing: 10) {
                        // Post with source label
                        Button { onPostWithSource(selectedSource) } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "paperplane.fill")
                                    .font(.systemScaled(14, weight: .semibold))
                                Text("Post with source label")
                                    .font(AMENFont.bold(15))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.25, green: 0.55, blue: 1.0),
                                                Color(red: 0.45, green: 0.72, blue: 1.0)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.35), radius: 8, y: 4)
                            )
                            .scaleEffect(postPressed ? 0.94 : 1.0)
                            .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: postPressed)
                        }
                        .buttonStyle(PlainButtonStyle())
                        ._onButtonGesture { pressing in postPressed = pressing } perform: {}

                        // Edit — write it yourself
                        Button { onEdit() } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "pencil")
                                    .font(.systemScaled(13, weight: .semibold))
                                Text("Write it myself")
                                    .font(AMENFont.bold(15))
                            }
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                    }
                            )
                            .scaleEffect(editPressed ? 0.94 : 1.0)
                            .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.6), value: editPressed)
                        }
                        .buttonStyle(PlainButtonStyle())
                        ._onButtonGesture { pressing in editPressed = pressing } perform: {}
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 36)
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.55), Color.white.opacity(0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: .black.opacity(0.10), radius: 24, y: 8)
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
                .onAppear {
                    withAnimation(Motion.adaptive(.spring(response: 0.40, dampingFraction: 0.70))) {
                        cardScale = 1.0
                        cardOpacity = 1.0
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Post Audience Sheet

