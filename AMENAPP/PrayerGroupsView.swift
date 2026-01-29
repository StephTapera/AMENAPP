//
//  PrayerGroupsView.swift
//  AMENAPP
//
//  Created by Steph on 1/17/26.
//

import SwiftUI

struct PrayerGroupsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: GroupTab = .discover
    @State private var searchText = ""
    @State private var showCreateGroup = false
    @Namespace private var tabAnimation
    
    enum GroupTab: String, CaseIterable {
        case discover = "Discover"
        case myGroups = "My Groups"
        case requests = "Requests"
        
        var icon: String {
            switch self {
            case .discover: return "house.fill"
            case .myGroups: return "antenna.radiowaves.left.and.right"
            case .requests: return "books.vertical.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prayer Groups")
                            .font(.custom("OpenSans-Bold", size: 32))
                        
                        Text("Pray together, grow together")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showCreateGroup = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.black)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search groups", text: $searchText)
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // Liquid Glass Pill Tab Selector
                HStack(spacing: 0) {
                    ForEach(GroupTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                selectedTab = tab
                                let haptic = UIImpactFeedbackGenerator(style: .medium)
                                haptic.impactOccurred()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(selectedTab == tab ? .white : .black.opacity(0.7))
                                
                                if selectedTab == tab {
                                    Text(tab.rawValue)
                                        .font(.custom("OpenSans-Bold", size: 15))
                                        .foregroundStyle(.white)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding(.horizontal, selectedTab == tab ? 20 : 16)
                            .padding(.vertical, 12)
                            .background(
                                Group {
                                    if selectedTab == tab {
                                        Capsule()
                                            .fill(Color.black)
                                            .matchedGeometryEffect(id: "selectedGroupTab", in: tabAnimation)
                                            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                                    } else {
                                        Capsule()
                                            .fill(Color.clear)
                                    }
                                }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        switch selectedTab {
                        case .discover:
                            DiscoverGroupsContent()
                        case .myGroups:
                            MyGroupsContent()
                        case .requests:
                            RequestsContent()
                        }
                    }
                    .padding(.vertical)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.custom("OpenSans-SemiBold", size: 16))
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupSheetView()
            }
        }
    }
}

// MARK: - Discover Groups Content
struct DiscoverGroupsContent: View {
    let groups = [
        PrayerGroup(
            name: "Morning Prayer Warriors",
            description: "Join us every morning at 6 AM for prayer and fellowship",
            members: 247,
            category: "Daily Prayer",
            icon: "sunrise.fill",
            color: .orange,
            isPrivate: false
        ),
        PrayerGroup(
            name: "Youth Ministry Prayers",
            description: "Praying for the next generation and youth leaders",
            members: 156,
            category: "Ministry",
            icon: "person.3.fill",
            color: .blue,
            isPrivate: false
        ),
        PrayerGroup(
            name: "Healing & Miracles",
            description: "Believing God for miracles and healing testimonies",
            members: 523,
            category: "Healing",
            icon: "cross.fill",
            color: .purple,
            isPrivate: false
        ),
        PrayerGroup(
            name: "Parents in Prayer",
            description: "Praying together for our children and families",
            members: 189,
            category: "Family",
            icon: "heart.fill",
            color: .pink,
            isPrivate: true
        )
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(groups) { group in
                PrayerGroupCard(group: group)
            }
        }
    }
}

// MARK: - Prayer Group Card
struct PrayerGroupCard: View {
    let group: PrayerGroup
    @State private var isJoined = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [group.color.opacity(0.2), group.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: group.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(group.color)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(group.name)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.primary)
                        
                        if group.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("\(group.members) members · \(group.category)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            
            Text(group.description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            
            // Action button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isJoined.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isJoined ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 16))
                    
                    Text(isJoined ? "Joined" : "Join Group")
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(isJoined ? .green : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isJoined ? Color.green.opacity(0.1) : Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isJoined ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
                        )
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .padding(.horizontal)
    }
}

// MARK: - My Groups Content
struct MyGroupsContent: View {
    let myGroups = [
        PrayerGroup(
            name: "Sunday Worship Team",
            description: "Praying for our worship services and team members",
            members: 45,
            category: "Worship",
            icon: "music.note",
            color: .blue,
            isPrivate: true
        ),
        PrayerGroup(
            name: "Bible Study Fellowship",
            description: "Weekly prayer for our study group",
            members: 23,
            category: "Bible Study",
            icon: "book.fill",
            color: .purple,
            isPrivate: false
        )
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(myGroups) { group in
                MyGroupCard(group: group)
            }
        }
    }
}

struct MyGroupCard: View {
    let group: PrayerGroup
    
    var body: some View {
        NavigationLink(destination: GroupDetailView(group: group)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [group.color.opacity(0.2), group.color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: group.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(group.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name)
                            .font(.custom("OpenSans-Bold", size: 17))
                            .foregroundStyle(.primary)
                        
                        Text("\(group.members) members")
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            
                            Text("3 new prayers")
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - Requests Content  
struct RequestsContent: View {
    let requests = [
        PrayerRequest(
            userName: "Sarah Johnson",
            userInitials: "SJ",
            content: "Please pray for my family as we navigate a difficult health diagnosis. We need God's peace and guidance.",
            time: "2h ago",
            prayerCount: 47,
            category: "Health",
            color: .red
        ),
        PrayerRequest(
            userName: "Michael Chen",
            userInitials: "MC",
            content: "Asking for prayers for my job interview tomorrow. Trusting God's plan! 🙏",
            time: "5h ago",
            prayerCount: 23,
            category: "Work",
            color: .blue
        ),
        PrayerRequest(
            userName: "Emily Martinez",
            userInitials: "EM",
            content: "Praise report! God answered our prayers for financial provision. Thank you all! ✨",
            time: "1d ago",
            prayerCount: 89,
            category: "Praise",
            color: .orange
        )
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            ForEach(requests) { request in
                GroupPrayerRequestCard(request: request)
            }
        }
    }
}

struct GroupPrayerRequestCard: View {
    let request: PrayerRequest
    @State private var hasPrayed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(request.color.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Text(request.userInitials)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(request.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.userName)
                        .font(.custom("OpenSans-Bold", size: 15))
                    
                    Text(request.time)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(request.category)
                    .font(.custom("OpenSans-SemiBold", size: 11))
                    .foregroundStyle(request.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(request.color.opacity(0.1))
                    )
            }
            
            Text(request.content)
                .font(.custom("OpenSans-Regular", size: 15))
                .lineSpacing(6)
            
            HStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        hasPrayed.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: hasPrayed ? "hands.sparkles.fill" : "hands.sparkles")
                            .font(.system(size: 16))
                        
                        Text(hasPrayed ? "Prayed" : "I'll Pray")
                            .font(.custom("OpenSans-Bold", size: 14))
                        
                        Text("(\(request.prayerCount + (hasPrayed ? 1 : 0)))")
                            .font(.custom("OpenSans-Regular", size: 13))
                    }
                    .foregroundStyle(hasPrayed ? .purple : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(hasPrayed ? Color.purple.opacity(0.1) : Color.black)
                            .overlay(
                                Capsule()
                                    .stroke(hasPrayed ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 2)
                            )
                    )
                }
                
                Button {
                    // Comment
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                        
                        Text("Encourage")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .padding(.horizontal)
    }
}

// MARK: - Group Detail View
struct GroupDetailView: View {
    @Environment(\.dismiss) var dismiss
    let group: PrayerGroup
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [group.color.opacity(0.2), group.color.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: group.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(group.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name)
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("\(group.members) members · \(group.category)")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(group.description)
                        .font(.custom("OpenSans-Regular", size: 15))
                        .lineSpacing(4)
                }
                .padding()
                
                Divider()
                
                // Recent prayers section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Prayers")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .padding(.horizontal)
                    
                    Text("Group prayer feed coming soon")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Create Prayer Group View
struct CreateGroupSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var groupDescription = ""
    @State private var selectedCategory = "Youth"
    @State private var selectedIcon = "person.3.fill"
    @State private var isPrivate = false
    
    let categories = ["Youth", "Family", "Health", "Missions", "Finance", "Marriage", "Other"]
    let icons = ["person.3.fill", "heart.circle.fill", "globe.americas.fill", "chart.line.uptrend.xyaxis", "heart.text.square.fill"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group Details") {
                    TextField("Group Name", text: $groupName)
                    
                    TextField("Description", text: $groupDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                }
                
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 24))
                                    .foregroundStyle(selectedIcon == icon ? .white : .black)
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedIcon == icon ? Color.blue : Color.gray.opacity(0.2))
                                    )
                            }
                        }
                    }
                }
                
                Section("Privacy") {
                    Toggle("Private Group", isOn: $isPrivate)
                }
            }
            .navigationTitle("Create Prayer Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        // Create group
                        dismiss()
                    }
                    .disabled(groupName.isEmpty || groupDescription.isEmpty)
                }
            }
        }
    }
}

// MARK: - Models
struct PrayerGroup: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let members: Int
    let category: String
    let icon: String
    let color: SwiftUI.Color
    let isPrivate: Bool
}

struct PrayerRequest: Identifiable {
    let id = UUID()
    let userName: String
    let userInitials: String
    let content: String
    let time: String
    let prayerCount: Int
    let category: String
    let color: SwiftUI.Color
}

#Preview("Prayer Groups") {
    PrayerGroupsView()
}
