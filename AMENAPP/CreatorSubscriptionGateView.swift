//
//  CreatorSubscriptionGateView.swift
//  AMENAPP
//
//  Full glass-card paywall overlay for subscriber-gated creator content.
//  Supports both the new (creatorId / benefits / price) API and the legacy
//  FaithCreator-based usage inside CreatorView.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - CreatorSubscriptionGateView

/// Primary variant — works with the CreatorProfile / Creator Studio system.
struct CreatorSubscriptionGateView: View {

    let creatorId:         String
    let creatorName:       String
    let subscriptionPrice: Double
    let benefits:          [String]
    let onSubscribe:       () -> Void
    let onTip:             () -> Void

    @State private var appear = false

    private let Color.accentColor = Color(red: 0.42, green: 0.28, blue: 1.00)
    private let Color.accentColor   = Color(red: 0.96, green: 0.62, blue: 0.04)

    var body: some View {
        ZStack {
            // Frosted backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .blur(radius: 2)

            gateCard
                .padding(.horizontal, 24)
                .scaleEffect(appear ? 1.0 : 0.88)
                .opacity(appear ? 1.0 : 0.0)
                .onAppear {
                    withAnimation(Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.75))) {
                        appear = true
                    }
                }
        }
    }

    // MARK: - Gate Card

    private var gateCard: some View {
        VStack(spacing: 0) {
            // Gradient header
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor, Color(red: 0.60, green: 0.28, blue: 0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.systemScaled(28, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(creatorName)
                        .font(AMENFont.bold(22))
                        .foregroundStyle(.white)
                    Text("This content is for subscribers")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.vertical, 28)
            }
            .clipShape(TopRoundedRect(radius: 20))

            // Body
            VStack(spacing: 18) {
                // Price
                (
                    Text(priceFormatted)
                        .font(AMENFont.bold(36))
                        .foregroundStyle(Color.white)
                    + Text(" /month")
                        .font(AMENFont.regular(18))
                        .foregroundStyle(Color.white.opacity(0.5))
                )

                // Benefits
                if !benefits.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(benefits, id: \.self) { benefit in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.systemScaled(16, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.accentColor)
                                Text(benefit)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.white.opacity(0.82))
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Subscribe CTA
                Button(action: onSubscribe) {
                    Text("Subscribe \(priceFormatted)/mo")
                        .font(AMENFont.bold(16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color(red: 0.60, green: 0.28, blue: 0.90)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: Color.accentColor.opacity(0.4), radius: 14, y: 5)
                        )
                }
                .buttonStyle(CoCreationPressStyle())

                // Tip link
                Button(action: onTip) {
                    Text("Support with a tip instead")
                        .font(AMENFont.semiBold(14))
                        .foregroundStyle(.white.opacity(0.45))
                        .underline(color: .white.opacity(0.2))
                }
                .buttonStyle(CoCreationPressStyle())
            }
            .padding(24)
            .background(BottomRoundedRect(radius: 20).fill(.ultraThinMaterial))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
    }

    private var priceFormatted: String { String(format: "$%.2f", subscriptionPrice) }
}

// MARK: - Legacy variant (FaithCreator-based, used in CreatorView)

struct CreatorSubscriptionGateLegacyView: View {
    let creator: FaithCreator
    var onSubscribe: (() -> Void)? = nil
    var onDismiss:   (() -> Void)? = nil

    @State private var isSubscribing = false
    @State private var showConfirm   = false
    @Environment(\.dismiss) private var dismiss

    private let Color.accentColor = Color(red: 0.96, green: 0.62, blue: 0.04)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                dragHandle
                VStack(spacing: 24) {
                    creatorHeader
                    benefitsList
                    priceRow
                    subscribeButton
                    maybeLaterButton
                }
                .padding(24)
                .padding(.bottom, 24)
            }
        }
    }

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 4)
            .padding(.top, 12)
    }

    private var creatorHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: creator.bannerColor), Color(hex: creator.bannerColor).opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                if !creator.avatarURL.isEmpty {
                    AsyncImage(url: URL(string: creator.avatarURL)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill").foregroundStyle(.white)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Image(systemName: creator.category.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(-2)
            )
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(creator.displayName)
                        .font(AMENFont.bold(20))
                        .foregroundStyle(.white)
                    if creator.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(Color.accentColor)
                            .font(.subheadline)
                    }
                }
                Text("@\(creator.handle) · \(creator.category.rawValue)")
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var benefitsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subscriber Benefits")
                .font(AMENFont.semiBold(14))
                .foregroundStyle(.white.opacity(0.6))
            ForEach([
                ("lock.open.fill",          "Exclusive content & teachings"),
                ("bell.badge.fill",         "Early access to new series"),
                ("person.fill.checkmark",   "Direct messaging with \(creator.displayName)"),
                ("gift.fill",               "Monthly digital goods"),
            ], id: \.0) { icon, text in
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.systemScaled(14))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    Text(text)
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var priceRow: some View {
        HStack {
            Text("Monthly subscription")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text("$\(String(format: "%.2f", creator.subscriptionPrice)) / mo")
                .font(AMENFont.bold(17))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 4)
    }

    private var subscribeButton: some View {
        Button { showConfirm = true } label: {
            HStack {
                if isSubscribing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "star.fill")
                    Text("Subscribe for $\(String(format: "%.2f", creator.subscriptionPrice))/mo")
                        .font(AMENFont.semiBold(16))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.62, blue: 0.04), Color(red: 0.94, green: 0.27, blue: 0.27)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .disabled(isSubscribing)
        .buttonStyle(CoCreationPressStyle())
        .alert("Subscribe to \(creator.displayName)?", isPresented: $showConfirm) {
            Button("Subscribe") { handleSubscribe() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("$\(String(format: "%.2f", creator.subscriptionPrice))/month. Cancel anytime.")
        }
    }

    private var maybeLaterButton: some View {
        Button {
            dismiss()
            onDismiss?()
        } label: {
            Text("Maybe Later")
                .font(AMENFont.regular(14))
                .foregroundStyle(.white.opacity(0.4))
        }
        .buttonStyle(CoCreationPressStyle())
    }

    private func handleSubscribe() {
        isSubscribing = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            guard let uid = Auth.auth().currentUser?.uid else { isSubscribing = false; return }
            lazy var db = Firestore.firestore()
            try? await db.collection("creatorSubscriptions").addDocument(data: [
                "subscriberId": uid,
                "creatorId":    creator.id,
                "price":        creator.subscriptionPrice,
                "createdAt":    FieldValue.serverTimestamp(),
                "status":       "active",
            ])
            try? await db.collection("creatorProfiles").document(creator.id)
                .updateData(["subscriberCount": FieldValue.increment(Int64(1))])
            await MainActor.run {
                isSubscribing = false
                onSubscribe?()
                dismiss()
            }
        }
    }
}

// MARK: - Shape helpers

private struct TopRoundedRect: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                 radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                 radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

private struct BottomRoundedRect: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                 radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                 radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
