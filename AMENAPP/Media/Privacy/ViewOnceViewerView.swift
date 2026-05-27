import SwiftUI
import FirebaseFirestore

// MARK: - ViewOnceViewerView

/// Full-screen viewer for a view-once image.
/// - Screenshot detection: blurs image and notifies sender via Firestore.
/// - Background detection: applies blur overlay while app is not active.
/// - Calls `onViewed()` when the user dismisses.
@MainActor
struct ViewOnceViewerView: View {
    var imageURL: URL
    var messageId: String
    var onViewed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var screenshotTaken = false
    @State private var isBlurredForBackground = false
    @State private var screenshotWarningVisible = false

    private let db = Firestore.firestore()

    // MARK: - Notification observers (retained per-view)
    private let screenshotObserver = NotificationCenter.default
        .publisher(for: UIApplication.userDidTakeScreenshotNotification)
    private let resignActiveObserver = NotificationCenter.default
        .publisher(for: UIApplication.willResignActiveNotification)
    private let becomeActiveObserver = NotificationCenter.default
        .publisher(for: UIApplication.didBecomeActiveNotification)

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dark background
            Color.black.ignoresSafeArea()

            // Photo
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .blur(radius: (screenshotTaken || isBlurredForBackground) ? 40 : 0)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionNormal),
                            value: screenshotTaken || isBlurredForBackground
                        )
                case .failure:
                    Image(systemName: "photo.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                case .empty:
                    AmenGlassLoadingSkeleton(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, height: 300)
                        .padding(40)
                @unknown default:
                    EmptyView()
                }
            }

            // Screenshot warning banner
            VStack {
                if screenshotWarningVisible {
                    screenshotBanner
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .top))
                        )
                }
                Spacer()
                closeHint
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            .padding(.horizontal, 20)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { handleDismiss() }
        .accessibilityLabel("View once photo. Screenshot detection active.")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to close")
        // Screenshot detection
        .onReceive(screenshotObserver) { _ in handleScreenshot() }
        // Background blur
        .onReceive(resignActiveObserver) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast)) {
                isBlurredForBackground = true
            }
        }
        .onReceive(becomeActiveObserver) { _ in
            withAnimation(reduceMotion ? nil : .easeOut(duration: LiquidGlassTokens.motionFast)) {
                isBlurredForBackground = false
            }
        }
    }

    // MARK: - Sub-views

    private var screenshotBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AmenTheme.Colors.statusWarning)
                .accessibilityHidden(true)
            Text("Screenshot detected — sender was notified")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(AmenTheme.Colors.surfaceElevated)
            } else {
                RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                    .fill(LiquidGlassTokens.blurElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.7)
                    }
            }
        }
        .shadow(
            color: LiquidGlassTokens.shadowFloating.color,
            radius: LiquidGlassTokens.shadowFloating.radius,
            y: LiquidGlassTokens.shadowFloating.y
        )
    }

    private var closeHint: some View {
        Text("Tap to close")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.70))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.35))
            }
    }

    // MARK: - Actions

    private func handleScreenshot() {
        guard !screenshotTaken else { return }
        screenshotTaken = true
        withAnimation(
            reduceMotion
                ? .easeOut(duration: LiquidGlassTokens.motionFast)
                : .spring(response: LiquidGlassTokens.motionNormal, dampingFraction: 0.80)
        ) {
            screenshotWarningVisible = true
        }
        db.collection("messages").document(messageId)
            .setData(["screenshotTaken": true], merge: true)
    }

    private func handleDismiss() {
        onViewed()
        dismiss()
    }
}
