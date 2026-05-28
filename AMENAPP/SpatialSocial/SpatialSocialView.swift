import SwiftUI

// The Spatial Social layer — surfaces contextual awareness, nearby gatherings,
// ephemeral live spaces, and intelligent introductions.
struct SpatialSocialView: View {
    @ObservedObject private var vm = SpatialSocialViewModel.shared // PERF: singleton → @ObservedObject

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Ambient signal banner
                    if let signal = vm.topAmbientSignal {
                        AmbientSignalBanner(signal: signal) {
                            vm.dismissAmbientSignal(signal)
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Environment context card
                    if vm.currentEnvironment.type != .unknown {
                        EnvironmentContextCard(environment: vm.currentEnvironment)
                    }

                    // Active ephemeral spaces
                    if !vm.activeEphemeralSpaces.isEmpty {
                        ephemeralSpacesSection
                    }

                    // Nearby gatherings
                    if !vm.nearbyGatherings.isEmpty {
                        nearbyGatheringsSection
                    }

                    // Smart introductions
                    if !vm.smartIntroductions.isEmpty {
                        smartIntroductionsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.initialize() }
        }
    }

    // MARK: - Ephemeral Spaces Section

    private var ephemeralSpacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live Spaces", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(vm.activeEphemeralSpaces) { space in
                EphemeralSpaceCard(space: space)
            }
        }
    }

    // MARK: - Nearby Gatherings Section

    private var nearbyGatheringsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gatherings Nearby", systemImage: "person.3.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(vm.nearbyGatherings) { gathering in
                NearbyGatheringCard(gathering: gathering) {
                    Task { await vm.createEphemeralSpace(for: gathering) }
                }
            }
        }
    }

    // MARK: - Smart Introductions Section

    private var smartIntroductionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("People You Might Know", systemImage: "sparkle.magnifyingglass")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Based on shared contexts — not location tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(vm.smartIntroductions.prefix(3)) { intro in
                SmartIntroductionCard(intro: intro) {
                    vm.dismissIntroduction(intro)
                }
            }
        }
    }
}

// MARK: - Ambient Signal Banner

struct AmbientSignalBanner: View {
    let signal: AmbientSignal
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: signalIcon)
                .foregroundStyle(signalColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.message)
                    .font(.subheadline.weight(.medium))
                if let detail = signal.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let action = signal.action {
                Button(action.label) {}
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var signalIcon: String {
        switch signal.type {
        case .nearbyGathering:       return "person.3.fill"
        case .communityMoment:       return "sparkles"
        case .environmentShift:      return "location.fill"
        case .connectionOpportunity: return "person.badge.plus"
        case .eventStarting:         return "calendar.badge.clock"
        case .serviceReminder:       return "building.columns.fill"
        }
    }

    private var signalColor: Color {
        switch signal.priority {
        case .high:   return .blue
        case .medium: return .orange
        case .low:    return .secondary
        }
    }
}

// MARK: - Environment Context Card

struct EnvironmentContextCard: View {
    let environment: SpatialEnvironment

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: environment.type.systemImage)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(.blue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("You're in \(environment.type.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(environment.broadArea)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Ephemeral Space Card

struct EphemeralSpaceCard: View {
    let space: EphemeralLiveSpace

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(.green.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "dot.radiowaves.right")
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(space.title)
                        .font(.subheadline.weight(.semibold))
                    Circle().fill(.green).frame(width: 6, height: 6)
                }
                Text("\(space.memberUIDs.count) member\(space.memberUIDs.count == 1 ? "" : "s") · \(space.broadLocation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Nearby Gathering Card

struct NearbyGatheringCard: View {
    let gathering: NearbyGathering
    let onCreate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: gathering.type.systemImage)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .background(.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(gathering.title)
                    .font(.subheadline.weight(.semibold))
                Text("\(gathering.countLabel) · \(gathering.broadLocation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if gathering.isOpenToJoin {
                Button(action: onCreate) {
                    Text("Join Space")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Smart Introduction Card

struct SmartIntroductionCard: View {
    let intro: SmartIntroduction
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.purple.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text(intro.targetDisplayName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(intro.targetDisplayName)
                        .font(.subheadline.weight(.semibold))
                    Text(intro.suggestedRelationshipType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Text(intro.introductionReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !intro.commonContexts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(intro.commonContexts.prefix(4), id: \.self) { ctx in
                            Text(ctx)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.purple.opacity(0.1), in: Capsule())
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button("Connect") {}
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.purple.opacity(0.12))
                    .foregroundStyle(.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Button("Not Now") { onDismiss() }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
