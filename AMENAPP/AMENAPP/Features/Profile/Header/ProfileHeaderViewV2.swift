import SwiftUI
import FirebaseAuth

public struct ProfileHeaderViewV2: View {
    let targetUserId: String
    let targetDisplayName: String
    let targetProfileImageURL: String?
    let targetBio: String?

    @State private var vm: ProfileHeaderViewModel
    @State private var activeSheet: ProfileHeaderSheet?

    @Environment(\.openURL) private var openURL

    public init(targetUserId: String, targetDisplayName: String,
                targetProfileImageURL: String? = nil, targetBio: String? = nil) {
        self.targetUserId = targetUserId
        self.targetDisplayName = targetDisplayName
        self.targetProfileImageURL = targetProfileImageURL
        self.targetBio = targetBio
        let viewerId = Auth.auth().currentUser?.uid ?? ""
        _vm = State(initialValue: ProfileHeaderViewModel(
            targetUserId: targetUserId,
            viewerUserId: viewerId
        ))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            avatarNameRow
            if let metrics = vm.payload?.profileMetrics {
                RedeemedCountsView(metrics: metrics) { _ in /* tap detail — future */ }
                    .accessibilityIdentifier("redeemedCounts")
            }
            if let bio = targetBio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Bio: \(bio)")
            }
            if let store = vm.linksStore {
                ProfileLinksView(store: store)
            }
            if let chipVM = vm.chipBarVM, !chipVM.resolvedChips.isEmpty {
                ActionChipBar(chips: chipVM.resolvedChips,
                              targetUserId: targetUserId) { route in
                    handleRoute(route)
                }
            }
            if let proVM = vm.proSurfaceVM,
               let insight = proVM.insight,
               let role = proVM.activeRole {
                ProSurfaceCard(insight: insight, role: role) {
                    if let url = URL(string: insight.deepLinkPath) {
                        openURL(url)
                    }
                }
            }
            if let pinStore = vm.pinnedPostsStore {
                if !pinStore.pinnedPreviews.isEmpty {
                    PinnedPostsRow(previews: pinStore.pinnedPreviews) { _ in }
                }
                PinEmptyStateCard(onTapPin: { activeSheet = .pinManager },
                                  isOwnProfile: vm.isOwnProfile)
            }
        }
        .task { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Avatar + Name Row

    private var avatarNameRow: some View {
        HStack(spacing: 12) {
            AsyncImage(url: targetProfileImageURL.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    Circle().fill(Color.accentColor.opacity(0.2))
                        .overlay(Text(String(targetDisplayName.prefix(2)).uppercased())
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary))
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .accessibilityLabel("Profile photo for \(targetDisplayName)")

            VStack(alignment: .leading, spacing: 4) {
                Text(targetDisplayName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                if let flags = vm.payload?.roleFlags {
                    roleBadge(flags)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func roleBadge(_ flags: ProfileRoleFlags) -> some View {
        if flags.isChurchAccount {
            chipLabel("Church", icon: "building.columns.fill")
        } else if flags.isMinistryLeader {
            chipLabel("Ministry Leader", icon: "building.2.fill")
        } else if flags.isMentor {
            chipLabel("Mentor", icon: "person.2.fill")
        } else if flags.isCreator {
            chipLabel("Creator", icon: "star.fill")
        }
    }

    private func chipLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("Role: \(text)")
    }

    // MARK: - Route Handling

    private func handleRoute(_ route: ActionChipRoute) {
        activeSheet = .chipRoute(route)
    }

    // MARK: - Sheet content

    @ViewBuilder
    private func sheetContent(_ sheet: ProfileHeaderSheet) -> some View {
        switch sheet {
        case .pinManager:
            if let store = vm.pinnedPostsStore {
                PinManagerView(store: store)
            }
        case .chipRoute(let route):
            chipRouteView(route)
        }
    }

    @ViewBuilder
    private func chipRouteView(_ route: ActionChipRoute) -> some View {
        switch route {
        case .bereanAbout(let userId):
            BereanAboutPersonView(
                targetUserId: userId,
                targetDisplayName: targetDisplayName,
                targetProfileImageURL: targetProfileImageURL
            )
        case .pray:
            Text("Prayer flow coming soon")
                .padding()
        case .message:
            Text("Message flow coming soon")
                .padding()
        case .verse:
            Text("Verse flow coming soon")
                .padding()
        case .visitChurch(let churchId):
            Text("Church: \(churchId)")
                .padding()
        case .give(let userId):
            Text("Giving flow for \(userId)")
                .padding()
        case .subscribe(let userId):
            Text("Subscribe flow for \(userId)")
                .padding()
        }
    }
}

// MARK: - Sheet Enum

private enum ProfileHeaderSheet: Identifiable {
    case pinManager
    case chipRoute(ActionChipRoute)

    var id: String {
        switch self {
        case .pinManager: return "pinManager"
        case .chipRoute(let r): return "route-\(r)"
        }
    }
}
