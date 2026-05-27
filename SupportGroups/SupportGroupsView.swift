import SwiftUI

struct SupportGroupsView: View {
    @StateObject private var service = SupportGroupService()
    @State private var selectedTab: GroupTab = .discover
    @State private var selectedGroup: SupportGroup? = nil
    @State private var showCreate = false

    enum GroupTab: String, CaseIterable { case discover = "Discover", myGroups = "My Groups" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(GroupTab.allCases, id: \.self) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented).padding()
                switch selectedTab {
                case .discover: discoverTab
                case .myGroups: myGroupsTab
                }
            }
            .navigationTitle("Support Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.90))
                    }
                    .accessibilityLabel("Create support group")
                }
            }
            .task { await service.loadRecommended(); service.startListeningMyGroups() }
            .sheet(item: $selectedGroup) { group in SupportGroupDetailView(group: group, service: service) }
            .sheet(isPresented: $showCreate) { CreateSupportGroupSheet(service: service) }
        }
    }

    private var discoverTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if service.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(service.recommendedGroups) { group in
                        SupportGroupCard(group: group, service: service).onTapGesture { selectedGroup = group }
                    }
                }
            }
            .padding(16)
        }
    }

    private var myGroupsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if service.myGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text("You haven't joined any groups yet").font(.custom("OpenSans-Regular", size: 15)).foregroundStyle(AmenTheme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(service.myGroups) { group in
                        SupportGroupCard(group: group, service: service).onTapGesture { selectedGroup = group }
                    }
                }
            }
            .padding(16)
        }
    }
}

struct SupportGroupCard: View {
    let group: SupportGroup
    let service: SupportGroupService
    @State private var isJoining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: group.category.icon).foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.90))
                Text(group.category.displayName).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                Spacer()
                Text("\(group.memberCount) members").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
            }
            Text(group.name).font(.custom("OpenSans-Bold", size: 16)).foregroundStyle(AmenTheme.Colors.textPrimary)
            Text(group.description).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary).lineLimit(2)
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("Led by \(group.leaderName)").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textTertiary)
                    if group.leaderVerified { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(Color(red: 0.40, green: 0.70, blue: 0.95)) }
                }
                Spacer()
                Button(isJoining ? "Joining..." : "Join") {
                    isJoining = true
                    Task { try? await service.joinGroup(groupId: group.id ?? ""); isJoining = false }
                }
                .font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(red: 0.60, green: 0.50, blue: 0.90)).cornerRadius(10)
                .disabled(isJoining)
                .accessibilityLabel("Join \(group.name)")
            }
        }
        .padding(14).background(AmenTheme.Colors.surfaceCard).cornerRadius(14)
        .accessibilityLabel(group.name)
    }
}
