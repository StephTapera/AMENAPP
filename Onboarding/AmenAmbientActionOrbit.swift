import SwiftUI

struct AmenOrbitProfile: Equatable {
    let displayName: String
    let username: String?
    let imageURL: URL?
    let isComplete: Bool

    var initials: String {
        let words = displayName.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        let value = String(letters).uppercased()
        return value.isEmpty ? "A" : value
    }
}

struct AmenOrbitAction: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let priority: Int

    static func onboardingActions(hasPhoto: Bool, hasChurch: Bool, hasInterests: Bool) -> [AmenOrbitAction] {
        var actions: [AmenOrbitAction] = []

        if !hasPhoto {
            actions.append(.init(id: "photo", title: "Add Photo", symbol: "camera.fill", priority: 0))
        }
        if !hasChurch {
            actions.append(.init(id: "church", title: "Find Church", symbol: "building.columns.fill", priority: 1))
        }
        if !hasInterests {
            actions.append(.init(id: "preferences", title: "Set Preferences", symbol: "slider.horizontal.3", priority: 2))
        }

        actions.append(.init(id: "prayer", title: "Start Prayer", symbol: "hands.sparkles.fill", priority: actions.count))
        actions.append(.init(id: "room", title: "Join Room", symbol: "person.2.fill", priority: actions.count))
        actions.append(.init(id: "invite", title: "Invite Friend", symbol: "person.badge.plus.fill", priority: actions.count))

        if hasPhoto && hasChurch && hasInterests {
            return [
                .init(id: "home", title: "Continue Home", symbol: "house.fill", priority: 0),
                .init(id: "prayer-room", title: "Join Prayer Room", symbol: "bubble.left.and.bubble.right.fill", priority: 1),
                .init(id: "berean", title: "Open Berean", symbol: "sparkles", priority: 2),
                .init(id: "post", title: "Create First Post", symbol: "square.and.pencil", priority: 3),
                .init(id: "church-local", title: "Find Local Church", symbol: "location.fill", priority: 4)
            ]
        }

        return Array(actions.prefix(6))
    }
}

struct AmenAmbientActionOrbit: View {
    let profile: AmenOrbitProfile
    let actions: [AmenOrbitAction]
    let onContinue: () -> Void
    var onActionSelected: (AmenOrbitAction) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var appeared = false
    @State private var orbitPhase = false
    @State private var activeIndex = 0
    @State private var ambientTask: Task<Void, Never>?

    private var isAccessibilitySize: Bool {
        dynamicTypeSize >= .accessibility1
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 28)

                VStack(spacing: 8) {
                    Text(profile.isComplete ? "Welcome to Amen" : "Almost there")
                        .font(.system(size: isAccessibilitySize ? 30 : 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)

                    Text(profile.isComplete ? "Your profile is ready. Here are the next good steps." : "Amen found a few helpful next steps for your profile.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.black.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                orbitStage
                    .frame(maxWidth: .infinity)
                    .frame(height: isAccessibilitySize ? 430 : 360)
                    .padding(.horizontal, 18)

                Button(action: onContinue) {
                    HStack(spacing: 8) {
                        Text(profile.isComplete ? "Continue" : "Finish Profile")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

                Spacer(minLength: 24)
            }
            .padding(.top, 10)
        }
        .onAppear(perform: startOrbit)
        .onDisappear {
            ambientTask?.cancel()
        }
    }

    private var orbitStage: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let centerSize = min(side * 0.48, 166)

            ZStack {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    OrbitChip(action: action, isActive: index == activeIndex, reduceTransparency: reduceTransparency) {
                        onActionSelected(action)
                    }
                    .offset(orbitOffset(index: index, count: actions.count, stageSize: side))
                    .scaleEffect(chipScale(for: index))
                    .opacity(chipOpacity(for: index))
                    .zIndex(index == activeIndex ? 2 : 1)
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 2.6), value: orbitPhase)
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 0.32), value: activeIndex)
                }

                ProfileGlassShell(profile: profile, size: centerSize, reduceTransparency: reduceTransparency)
                    .scaleEffect(orbitPhase && !reduceMotion ? 1.025 : 1)
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 2.6), value: orbitPhase)
                    .zIndex(3)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96)
        }
    }

    private func startOrbit() {
        ambientTask?.cancel()

        if reduceMotion {
            appeared = true
            orbitPhase = true
            activeIndex = 0
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            appeared = true
        }

        withAnimation(.easeInOut(duration: 2.6)) {
            orbitPhase = true
        }

        ambientTask = Task { @MainActor in
            guard actions.count > 1 else { return }
            for index in actions.indices.dropFirst() {
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }
                activeIndex = index
            }
            try? await Task.sleep(for: .milliseconds(640))
            guard !Task.isCancelled else { return }
            activeIndex = 0
        }
    }

    private func orbitOffset(index: Int, count: Int, stageSize: CGFloat) -> CGSize {
        guard count > 0 else { return .zero }

        let baseRadius = min(priorityRadius(for: index), stageSize * 0.38)
        let baseAngle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
        let drift = reduceMotion ? 0 : (orbitPhase ? 0.24 : -0.16)
        let breathingRadius = reduceMotion ? baseRadius : (orbitPhase ? baseRadius + 8 : baseRadius - 8)
        let priorityLift = index == activeIndex ? CGFloat(-5) : 0

        return CGSize(
            width: cos(baseAngle + drift) * breathingRadius,
            height: sin(baseAngle + drift) * breathingRadius + priorityLift
        )
    }

    private func priorityRadius(for index: Int) -> CGFloat {
        switch index {
        case 0: return 112
        case 1: return 130
        case 2: return 142
        default: return 152
        }
    }

    private func chipScale(for index: Int) -> CGFloat {
        guard appeared else { return 0.88 }
        return index == activeIndex ? 1.04 : 0.96
    }

    private func chipOpacity(for index: Int) -> Double {
        guard appeared else { return 0 }
        return index == activeIndex ? 1 : 0.72
    }
}

private struct OrbitChip: View {
    let action: AmenOrbitAction
    let isActive: Bool
    let reduceTransparency: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label(action.title, systemImage: action.symbol)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .foregroundStyle(.black.opacity(isActive ? 0.92 : 0.68))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .frame(minHeight: 38)
                .background(chipBackground)
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(reduceTransparency ? 0.0 : 0.58), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isActive ? 0.14 : 0.08), radius: isActive ? 16 : 10, x: 0, y: isActive ? 8 : 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }

    @ViewBuilder
    private var chipBackground: some View {
        if reduceTransparency {
            Capsule().fill(Color.white)
        } else {
            Capsule()
                .fill(.regularMaterial)
                .glassEffect(Glass.regular.interactive(), in: Capsule())
        }
    }
}

private struct ProfileGlassShell: View {
    let profile: AmenOrbitProfile
    let size: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        VStack(spacing: 10) {
            avatar
                .frame(width: size * 0.50, height: size * 0.50)

            VStack(spacing: 3) {
                Text(profile.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                if let username = profile.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black.opacity(0.54))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }
        }
        .padding(18)
        .frame(width: size, height: size)
        .background(shellBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(reduceTransparency ? 0 : 0.64), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var avatar: some View {
        if let imageURL = profile.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    initialsAvatar
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Circle()
            .fill(Color.black.opacity(0.06))
            .overlay {
                Text(profile.initials)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.72))
            }
    }

    @ViewBuilder
    private var shellBackground: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white)
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(.regularMaterial)
                .glassEffect(Glass.regular.interactive(), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
    }
}

#Preview {
    AmenAmbientActionOrbit(
        profile: AmenOrbitProfile(
            displayName: "Steph Tapera",
            username: "steph",
            imageURL: nil,
            isComplete: false
        ),
        actions: AmenOrbitAction.onboardingActions(hasPhoto: false, hasChurch: false, hasInterests: true),
        onContinue: {}
    )
}
