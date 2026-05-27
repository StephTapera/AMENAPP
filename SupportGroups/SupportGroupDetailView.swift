import SwiftUI

struct SupportGroupDetailView: View {
    let group: SupportGroup
    let service: SupportGroupService
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DetailTab = .feed
    @State private var posts: [SupportGroupPost] = []
    @State private var showComposer = false

    enum DetailTab: String, CaseIterable { case feed = "Feed", members = "Members", resources = "Resources", guidelines = "Guidelines" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupHeader
                tabPicker
                tabContent
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showComposer) { SupportGroupComposer(group: group) }
    }

    private var groupHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").foregroundStyle(AmenTheme.Colors.textPrimary)
                }
                .accessibilityLabel("Go back")
                Spacer()
                Text(group.visibility.displayName)
                    .font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(AmenTheme.Colors.surfaceChip).cornerRadius(8)
            }
            .padding(.horizontal, 16).padding(.top, 8)
            HStack {
                Image(systemName: group.category.icon).font(.title2).foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.90))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.custom("OpenSans-Bold", size: 20)).foregroundStyle(AmenTheme.Colors.textPrimary)
                    Text("\(group.memberCount) members • Led by \(group.leaderName)").font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(AmenTheme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            Text(group.description).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textSecondary).lineLimit(3).padding(.horizontal, 16)
        }
        .padding(.vertical, 12).background(AmenTheme.Colors.backgroundPrimary)
    }

    private var tabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) { selectedTab = tab }
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.rawValue).font(.custom(selectedTab == tab ? "OpenSans-Bold" : "OpenSans-Regular", size: 14)).foregroundStyle(selectedTab == tab ? Color(red: 0.60, green: 0.50, blue: 0.90) : AmenTheme.Colors.textSecondary)
                            Rectangle().fill(selectedTab == tab ? Color(red: 0.60, green: 0.50, blue: 0.90) : Color.clear).frame(height: 2)
                        }
                        .padding(.horizontal, 12)
                    }
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .feed:
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(posts) { post in groupPostCard(post: post) }
                        if posts.isEmpty { Text("Be the first to post in this group.").font(.custom("OpenSans-Regular", size: 15)).foregroundStyle(AmenTheme.Colors.textTertiary).padding(.top, 60) }
                    }.padding(16)
                }
                Button { showComposer = true } label: {
                    Image(systemName: "square.and.pencil").font(.title2).foregroundStyle(.white).padding(14).background(Color(red: 0.60, green: 0.50, blue: 0.90)).clipShape(Circle())
                }
                .padding(20)
                .accessibilityLabel("Write post")
            }
        case .members:
            ScrollView { LazyVStack(spacing: 8) { }.padding(16) }
        case .resources:
            ScrollView { Text("Resources coming soon.").font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textTertiary).padding(20) }
        case .guidelines:
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(group.guidelines.enumerated()), id: \.offset) { _, guideline in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.60, green: 0.50, blue: 0.90))
                            Text(guideline).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                        }
                    }
                    if group.guidelines.isEmpty { Text("No guidelines provided.").font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textTertiary) }
                }.padding(16)
            }
        }
    }

    private func groupPostCard(post: SupportGroupPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(post.isAnonymous ? "Anonymous" : (post.authorName ?? "Member")).font(.custom("OpenSans-Bold", size: 13)).foregroundStyle(post.isAnonymous ? AmenTheme.Colors.textTertiary : AmenTheme.Colors.textPrimary)
                Spacer()
                if let ts = post.createdAt?.dateValue() { Text(ts.formatted(.relative(presentation: .named))).font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(AmenTheme.Colors.textTertiary) }
            }
            Text(post.content).font(.custom("OpenSans-Regular", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary).lineSpacing(4)
            HStack {
                Label("\(post.hearts)", systemImage: "heart").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
            }
        }
        .padding(12).background(AmenTheme.Colors.surfaceCard).cornerRadius(12)
        .accessibilityLabel(post.isAnonymous ? "Anonymous post" : "Post by \(post.authorName ?? "member")")
    }
}
