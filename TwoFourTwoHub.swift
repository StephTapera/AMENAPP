import SwiftUI

// MARK: - 242 Hub
// Acts 2:42 — The four pillars of early church life

struct TwoFourTwoHub: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPillar: TwoFourTwoPillar? = nil
    @State private var showSubscription = false
    @State private var selectedFeature: TwoFourTwoFeature? = nil
    @State private var headerAppeared = false
    @State private var userTier: AMENSubscriptionTier = .free

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hubHeader
                        .padding(.top, 56)
                        .padding(.horizontal, 24)
                    pillarTabRow
                        .padding(.top, 32)
                        .padding(.horizontal, 20)
                    featureList
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            }

            // Back button
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.leading, 16)
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(item: $selectedFeature) { feature in
            FeatureDetailSheet(feature: feature, userTier: userTier, onUpgrade: { showSubscription = true })
        }
        .sheet(isPresented: $showSubscription) {
            TwoFourTwoSubscriptionView(currentTier: $userTier)
        }
        .preferredColorScheme(.dark)
    }

    private var hubHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            GlassFolderIcon(size: 64)
                .scaleEffect(headerAppeared ? 1.0 : 0.7)
                .opacity(headerAppeared ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) { headerAppeared = true }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("242").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("resources").font(.system(size: 32, weight: .light, design: .rounded)).foregroundColor(.white.opacity(0.45))
                }
                Text("Acts 2:42 · teaching · fellowship · table · prayer")
                    .font(.system(size: 12, design: .rounded)).foregroundColor(.white.opacity(0.35)).lineSpacing(2)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pillarTabRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PillarTab(label: "all", icon: "square.grid.2x2", color: .white, isSelected: selectedPillar == nil) { selectedPillar = nil }
                ForEach(TwoFourTwoPillar.allCases, id: \.self) { pillar in
                    PillarTab(label: pillar.rawValue, icon: pillar.icon, color: pillar.color, isSelected: selectedPillar == pillar) { selectedPillar = pillar }
                }
            }
        }
    }

    private var featureList: some View {
        let features = selectedPillar == nil ? TwoFourTwoFeature.all : TwoFourTwoFeature.features(for: selectedPillar!)
        return VStack(spacing: 1) {
            ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                FeatureRow(feature: feature, userTier: userTier, isFirst: index == 0, isLast: index == features.count - 1) {
                    if feature.isComingSoon { return }
                    if userTier >= feature.requiredTier { selectedFeature = feature }
                    else { showSubscription = true }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 1, opacity: 0.04))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 12)
    }
}

// MARK: - 3D Glass Folder

struct GlassFolderIcon: View {
    let size: CGFloat
    @State private var floating = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(Color(red: 0.35, green: 0.55, blue: 0.98).opacity(0.20))
                .frame(width: size * 1.1, height: size * 1.1).blur(radius: 10)
            RoundedRectangle(cornerRadius: size * 0.14)
                .fill(Color(red: 0.45, green: 0.60, blue: 0.95))
                .frame(width: size, height: size * 0.72).offset(y: size * 0.04)
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(Color(red: 0.50, green: 0.64, blue: 0.98))
                .frame(width: size * 0.38, height: size * 0.18)
                .offset(x: -size * 0.25, y: -size * 0.27)
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(LinearGradient(colors: [Color(red: 0.70, green: 0.80, blue: 0.99), Color(red: 0.45, green: 0.60, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size * 0.68).offset(y: size * 0.06)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.12)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.45), Color.clear], startPoint: .topLeading, endPoint: .center))
                        .frame(width: size, height: size * 0.68).offset(y: size * 0.06)
                )
            Capsule().fill(Color.white.opacity(0.50)).frame(width: size * 0.22, height: size * 0.06).offset(x: -size * 0.20, y: -size * 0.04)
        }
        .frame(width: size, height: size)
        .offset(y: floating ? -3 : 0)
        .onAppear { withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { floating = true } }
    }
}

// MARK: - Pillar Tab

private struct PillarTab: View {
    let label: String; let icon: String; let color: Color; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(isSelected ? .black : .white.opacity(0.55))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(Capsule().fill(isSelected ? color : Color.white.opacity(0.07)).overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.10), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let feature: TwoFourTwoFeature; let userTier: AMENSubscriptionTier
    let isFirst: Bool; let isLast: Bool; let action: () -> Void
    private var isLocked: Bool { userTier < feature.requiredTier }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(feature.iconColor.opacity(isLocked ? 0.35 : 1.0))
                    Image(systemName: feature.iconName).font(.system(size: 16, weight: .medium)).foregroundColor(.white.opacity(isLocked ? 0.5 : 1.0))
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(feature.name).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundColor(isLocked ? .white.opacity(0.40) : .white)
                        if feature.isComingSoon { comingSoonBadge } else if isLocked { tierBadge }
                    }
                    Text(feature.tagline).font(.system(size: 12, design: .rounded)).foregroundColor(.white.opacity(isLocked ? 0.22 : 0.45))
                }
                Spacer()
                if feature.isComingSoon { Image(systemName: "clock").font(.system(size: 13)).foregroundColor(.white.opacity(0.20)) }
                else if isLocked { Image(systemName: "lock.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.22)) }
                else { Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.25)) }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5), alignment: .bottom)
        .opacity(feature.isComingSoon ? 0.55 : 1.0)
    }

    private var comingSoonBadge: some View {
        Text("soon").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundColor(Color(white: 0.55))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.07)).overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)))
    }
    private var tierBadge: some View {
        Text(feature.requiredTier.displayName).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundColor(feature.requiredTier.badgeColor.opacity(0.85))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(feature.requiredTier.badgeColor.opacity(0.12)).overlay(Capsule().strokeBorder(feature.requiredTier.badgeColor.opacity(0.25), lineWidth: 0.5)))
    }
}

// MARK: - Feature Detail Sheet

struct FeatureDetailSheet: View {
    let feature: TwoFourTwoFeature; let userTier: AMENSubscriptionTier; let onUpgrade: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.05, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 4).padding(.top, 12).padding(.bottom, 24)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(feature.iconColor).frame(width: 64, height: 64).shadow(color: feature.iconColor.opacity(0.35), radius: 14, x: 0, y: 6)
                                Image(systemName: feature.iconName).font(.system(size: 28, weight: .medium)).foregroundColor(.white)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.name).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundColor(.white)
                                Text(feature.pillar.rawValue.uppercased()).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundColor(feature.pillar.color).tracking(1.2)
                            }
                        }
                        .padding(.horizontal, 24)
                        Text(feature.description).font(.system(size: 16, weight: .regular, design: .serif)).foregroundColor(.white.opacity(0.80)).lineSpacing(6).padding(.horizontal, 24)
                        tierInfoCard.padding(.horizontal, 24)
                        ctaButton.padding(.horizontal, 24).padding(.bottom, 40)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tierInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.requiredTier == .free ? "checkmark.circle.fill" : "lock.fill").font(.system(size: 14)).foregroundColor(feature.requiredTier.badgeColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("requires \(feature.requiredTier.displayName)").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.75))
                Text(feature.requiredTier.price).font(.system(size: 12, design: .rounded)).foregroundColor(.white.opacity(0.40))
            }
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(feature.requiredTier.badgeColor.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(feature.requiredTier.badgeColor.opacity(0.20), lineWidth: 0.6)))
    }

    @ViewBuilder
    private var ctaButton: some View {
        if feature.requiredTier.isContactSales {
            Link(destination: URL(string: "mailto:amenappmarketing@gmail.com?subject=Enterprise%20Inquiry%20-%20\(feature.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? feature.name)")!) {
                ctaLabel("contact sales team", icon: "envelope.fill")
            }
        } else if userTier >= feature.requiredTier {
            Button { dismiss() } label: { ctaLabel("open \(feature.name.lowercased())", icon: "arrow.right") }
        } else {
            Button(action: onUpgrade) { ctaLabel("unlock with \(feature.requiredTier.displayName)", icon: "lock.open.fill") }
        }
    }

    private func ctaLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium))
            Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(feature.iconColor).shadow(color: feature.iconColor.opacity(0.30), radius: 14, x: 0, y: 6))
    }
}
