// BereanProjectsView.swift
// AMEN Berean — Projects + Folders workspace.
// White Liquid Glass design. Card grid, collections scroll, memory indicator.

import SwiftUI

// MARK: - Models

struct BereanProject: Identifiable, Codable {
    let id: UUID
    var title: String
    var iconSymbol: String
    var colorKey: String          // maps to Color at render time
    var description: String
    var chatCount: Int
    var isPinned: Bool
    var memoryEnabled: Bool
    var lastUpdated: Date
    var folder: String?           // optional folder grouping

    static func empty(title: String = "") -> BereanProject {
        BereanProject(id: UUID(), title: title, iconSymbol: "folder",
                      colorKey: "indigo", description: "", chatCount: 0,
                      isPinned: false, memoryEnabled: true, lastUpdated: Date(), folder: nil)
    }
}

// MARK: - Persistence

enum BereanProjectStore {
    static let key = "amen_berean_projects_v2"

    static func load() -> [BereanProject] {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([BereanProject].self, from: data) {
            return saved
        }
        return defaultProjects
    }

    static func save(_ projects: [BereanProject]) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static let defaultProjects: [BereanProject] = [
        BereanProject(id: UUID(), title: "Bible Study", iconSymbol: "book.pages",
                      colorKey: "indigo", description: "Personal scripture study and reflections",
                      chatCount: 4, isPinned: true, memoryEnabled: true, lastUpdated: .now, folder: nil),
        BereanProject(id: UUID(), title: "Prayer Journal", iconSymbol: "hands.sparkles",
                      colorKey: "purple", description: "Prayers, intercessions, answered prayers",
                      chatCount: 7, isPinned: false, memoryEnabled: true,
                      lastUpdated: Calendar.current.date(byAdding: .day, value: -1, to: .now)!, folder: nil),
        BereanProject(id: UUID(), title: "Church Notes", iconSymbol: "doc.plaintext",
                      colorKey: "teal", description: "Sermon notes and teaching materials",
                      chatCount: 3, isPinned: false, memoryEnabled: false,
                      lastUpdated: Calendar.current.date(byAdding: .day, value: -3, to: .now)!, folder: nil),
    ]
}

// MARK: - Colour Tokens

private extension Color {
    static func bereanProjectAccent(_ key: String) -> Color {
        switch key {
        case "indigo":  return Color(red: 0.35, green: 0.30, blue: 0.90)
        case "purple":  return Color(red: 0.55, green: 0.20, blue: 0.85)
        case "teal":    return Color(red: 0.15, green: 0.60, blue: 0.58)
        case "coral":   return Color(red: 0.88, green: 0.38, blue: 0.28)
        case "navy":    return Color(red: 0.10, green: 0.20, blue: 0.55)
        case "sage":    return Color(red: 0.25, green: 0.55, blue: 0.35)
        case "amber":   return Color(red: 0.85, green: 0.55, blue: 0.10)
        default:        return Color(red: 0.30, green: 0.35, blue: 0.80)
        }
    }

    static let bpBG        = Color(red: 0.975, green: 0.975, blue: 0.975)
    static let bpCard      = Color.white
    static let bpStroke    = Color(white: 0, opacity: 0.06)
    static let bpPrimary   = Color(white: 0.10)
    static let bpSecondary = Color(white: 0.48)
    static let bpTertiary  = Color(white: 0.66)
}

// MARK: - Collections Data

private struct BereanCollection: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let colorKey: String
}

private let bereanCollections: [BereanCollection] = [
    BereanCollection(name: "Bible Study",          icon: "book.pages",         colorKey: "indigo"),
    BereanCollection(name: "Sermon Prep",          icon: "mic",                colorKey: "teal"),
    BereanCollection(name: "Prayer Journal",       icon: "hands.sparkles",     colorKey: "purple"),
    BereanCollection(name: "Personal Reflection",  icon: "sparkles",           colorKey: "amber"),
    BereanCollection(name: "Life Planning",        icon: "list.bullet.clipboard", colorKey: "sage"),
    BereanCollection(name: "AMEN Build",           icon: "hammer",             colorKey: "coral"),
]

// MARK: - BereanProjectsView

struct BereanProjectsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onProjectSelected: ((BereanProject) -> Void)? = nil

    @State private var projects: [BereanProject] = BereanProjectStore.load()
    @State private var searchQuery = ""
    @State private var showNewProject = false
    @State private var selectedProject: BereanProject? = nil
    @State private var showMemorySettings = false

    private var filtered: [BereanProject] {
        searchQuery.isEmpty ? projects : projects.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery)
        }
    }
    private var pinned: [BereanProject]   { filtered.filter { $0.isPinned } }
    private var unpinned: [BereanProject] { filtered.filter { !$0.isPinned } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBG.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Memory banner
                        memoryBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        // My Conversations — always visible pinned section
                        sectionHeader("MY CONVERSATIONS")
                        myConversationsRow

                        // Pinned projects
                        if !pinned.isEmpty {
                            sectionHeader("PINNED")
                            projectGrid(pinned)
                        }

                        // All projects
                        sectionHeader(pinned.isEmpty ? "PROJECTS" : "ALL PROJECTS")
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            projectGrid(unpinned)
                        }

                        // Collections
                        sectionHeader("COLLECTIONS")
                        collectionsRow
                            .padding(.bottom, 4)

                        Spacer().frame(height: 100)
                    }
                    .padding(.top, 4)
                }
                .searchable(text: $searchQuery, prompt: "Search projects")
            }
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(Color.bpSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewProject = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.systemScaled(14, weight: .semibold))
                            Text("New Project")
                                .font(.systemScaled(14, weight: .semibold))
                        }
                    }
                }
            }
            .sheet(isPresented: $showNewProject) {
                BereanNewProjectSheet { newProject in
                    projects.insert(newProject, at: 0)
                    BereanProjectStore.save(projects)
                }
            }
            .sheet(item: $selectedProject) { project in
                BereanProjectDetailView(project: project)
            }
        }
    }

    // MARK: - Memory Banner

    private var memoryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain")
                .font(.systemScaled(13, weight: .medium))
                .foregroundStyle(Color.bpSecondary)

            Text("Berean remembers your preferences")
                .font(.systemScaled(13))
                .foregroundStyle(Color.bpSecondary)

            Spacer()

            Button { showMemorySettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.systemScaled(14))
                    .foregroundStyle(Color.bpTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.bpCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.bpStroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: - My Conversations Row

    private var myConversationsRow: some View {
        VStack(spacing: 0) {
            Button {
                // Navigate to all conversations
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.92)).frame(width: 44, height: 44)
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.systemScaled(18, weight: .medium))
                            .foregroundStyle(Color.bpPrimary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My Conversations")
                            .font(.systemScaled(15, weight: .semibold))
                            .foregroundStyle(Color.bpPrimary)
                        Text("All recent Berean chats")
                            .font(.systemScaled(12))
                            .foregroundStyle(Color.bpSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.systemScaled(11, weight: .medium))
                        .foregroundStyle(Color.bpTertiary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 78)
        }
    }

    // MARK: - Project Grid (2 column)

    private func projectGrid(_ items: [BereanProject]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(items) { project in
                projectCard(project)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private func projectCard(_ project: BereanProject) -> some View {
        let accent = Color.bereanProjectAccent(project.colorKey)

        return Button {
            if let handler = onProjectSelected {
                handler(project)
                dismiss()
            } else {
                selectedProject = project
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: project.iconSymbol)
                        .font(.systemScaled(18, weight: .medium))
                        .foregroundStyle(accent)
                }

                // Name
                Text(project.title)
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(Color.bpPrimary)
                    .lineLimit(1)

                // Stats
                HStack(spacing: 4) {
                    Text("\(project.chatCount) chats")
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.bpSecondary)
                    Spacer()
                    Text(relativeDate(project.lastUpdated))
                        .font(.systemScaled(11))
                        .foregroundStyle(Color.bpTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.bpCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.bpStroke, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { projectContextMenu(project) }
    }

    // MARK: - Collections Row

    private var collectionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(bereanCollections) { collection in
                    collectionChip(collection)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func collectionChip(_ collection: BereanCollection) -> some View {
        let accent = Color.bereanProjectAccent(collection.colorKey)
        return Button {
            // Navigate to collection
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collection.icon)
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(accent)
                Text(collection.name)
                    .font(.systemScaled(13, weight: .medium))
                    .foregroundStyle(Color.bpPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.bpCard)
                    .overlay(Capsule().strokeBorder(Color.bpStroke, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Header

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.systemScaled(11, weight: .semibold)).kerning(0.8)
            .foregroundStyle(Color.bpTertiary)
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 6)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func projectContextMenu(_ project: BereanProject) -> some View {
        Button { selectedProject = project } label: {
            Label("Open", systemImage: "arrow.right.square")
        }
        Button {
            if let idx = projects.firstIndex(where: { $0.id == project.id }) {
                projects[idx].isPinned.toggle()
                BereanProjectStore.save(projects)
            }
        } label: {
            Label(project.isPinned ? "Unpin" : "Pin",
                  systemImage: project.isPinned ? "pin.slash" : "pin")
        }
        Divider()
        Button(role: .destructive) {
            withAnimation(reduceMotion ? nil : .default) {
                projects.removeAll { $0.id == project.id }
                BereanProjectStore.save(projects)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.systemScaled(38))
                .foregroundStyle(Color.bpTertiary)
            Text("No projects yet")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(Color.bpPrimary)
            Text("Organize Bible studies, prayers, church notes,\nand more into projects.")
                .font(.systemScaled(14))
                .foregroundStyle(Color.bpSecondary)
                .multilineTextAlignment(.center)
            Button { showNewProject = true } label: {
                Text("Create your first project")
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bereanProjectAccent("indigo"))
            }
        }
        .padding(.top, 60).padding(.horizontal, 40)
    }

    private func relativeDate(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days)d ago"
        }
    }
}

// MARK: - BereanProjectDetailView

struct BereanProjectDetailView: View {
    let project: BereanProject
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ProjTab = .overview
    @StateObject private var convService = BereanConversationService.shared
    private let accent: Color

    enum ProjTab: String, CaseIterable {
        case overview = "Overview"
        case chats    = "Chats"
        case saved    = "Saved"
        case notes    = "Notes"
    }

    init(project: BereanProject) {
        self.project = project
        self.accent = Color.bereanProjectAccent(project.colorKey)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBG.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Tab selector
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(ProjTab.allCases, id: \.self) { tab in
                                Button {
                                    withAnimation(Motion.adaptive(.spring(response: 0.30, dampingFraction: 0.78))) {
                                        selectedTab = tab
                                    }
                                } label: {
                                    Text(tab.rawValue)
                                        .font(.systemScaled(13, weight: selectedTab == tab ? .semibold : .regular))
                                        .foregroundStyle(selectedTab == tab ? accent : Color.bpSecondary)
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background {
                                            if selectedTab == tab {
                                                Capsule().fill(accent.opacity(0.10))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            switch selectedTab {
                            case .overview: overviewTab
                            case .chats:    chatsTab
                            case .saved:
                                emptyPlaceholder(
                                    icon: "bookmark",
                                    text: "No saved outputs yet.\nSave responses from any chat to see them here."
                                )
                            case .notes:
                                emptyPlaceholder(
                                    icon: "note.text",
                                    text: "No notes yet.\nAdd notes from a chat or create one directly."
                                )
                            }
                        }
                        .padding(.top, 16)
                    }
                }
            }
            .navigationTitle(project.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(Color.bpSecondary)
                    }
                }
            }
        }
    }

    // MARK: Overview

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent.opacity(0.12)).frame(width: 52, height: 52)
                        Image(systemName: project.iconSymbol)
                            .font(.systemScaled(22, weight: .medium)).foregroundStyle(accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title)
                            .font(.systemScaled(18, weight: .bold)).foregroundStyle(Color.bpPrimary)
                        if !project.description.isEmpty {
                            Text(project.description)
                                .font(.systemScaled(13)).foregroundStyle(Color.bpSecondary)
                        }
                    }
                }
                HStack(spacing: 20) {
                    statPill("\(project.chatCount)", "chats")
                    statPill(project.memoryEnabled ? "On" : "Off", "memory")
                    statPill("Active", "status")
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.bpCard)
                    .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.bpStroke, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)

            Text("QUICK ACTIONS")
                .font(.systemScaled(11, weight: .semibold)).kerning(0.8)
                .foregroundStyle(Color.bpTertiary).padding(.horizontal, 20)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                quickActionTile("New Chat",        icon: "plus.bubble")
                quickActionTile("Add Note",        icon: "note.text.badge.plus")
                quickActionTile("Study Scripture", icon: "book.pages")
                quickActionTile("Create Prayer",   icon: "hands.sparkles")
            }
            .padding(.horizontal, 16)

            Spacer().frame(height: 80)
        }
    }

    @ViewBuilder
    private func statPill(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.systemScaled(15, weight: .bold)).foregroundStyle(accent)
            Text(label).font(.systemScaled(11)).foregroundStyle(Color.bpTertiary)
        }
    }

    @ViewBuilder
    private func quickActionTile(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(14, weight: .medium)).foregroundStyle(accent)
            Text(title)
                .font(.systemScaled(13, weight: .semibold)).foregroundStyle(Color.bpPrimary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bpCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.bpStroke, lineWidth: 0.5)
                )
        )
    }

    // MARK: Chats

    private var chatsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if convService.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if convService.conversations.isEmpty {
                emptyPlaceholder(icon: "bubble.left", text: "No chats in this project yet.\nStart a new chat to begin.")
            } else {
                ForEach(convService.conversations) { conv in
                    conversationRow(conv)
                }
            }
        }
        .task {
            await convService.fetchConversations(projectId: project.id.uuidString)
        }
    }

    @ViewBuilder
    private func conversationRow(_ conv: BereanConversation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left")
                .font(.systemScaled(15))
                .foregroundStyle(accent.opacity(0.7))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title)
                    .font(.systemScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(conv.messageCount) messages")
                    Text("·")
                    Text(conv.relativeDate)
                }
                .font(.systemScaled(12))
                .foregroundStyle(Color.bpSecondary)
                if let preview = conv.lastMessagePreview {
                    Text(preview)
                        .font(.systemScaled(12))
                        .foregroundStyle(Color.bpTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.systemScaled(11))
                .foregroundStyle(Color.bpTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        Divider().padding(.leading, 64)
    }

    @ViewBuilder
    private func emptyPlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.systemScaled(32)).foregroundStyle(Color.bpTertiary)
            Text(text)
                .font(.systemScaled(14)).foregroundStyle(Color.bpSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 40)
    }
}

// MARK: - BereanNewProjectSheet

struct BereanNewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onCreate: (BereanProject) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var selectedIconIndex = 0
    @State private var selectedColorKey = "indigo"
    @FocusState private var titleFocused: Bool

    private let icons = ["folder", "book.pages", "hands.sparkles", "doc.plaintext",
                         "lightbulb", "heart.text.square", "person.2", "building.columns",
                         "cross", "graduationcap", "star", "music.note"]
    private let colorKeys = ["indigo", "purple", "teal", "coral", "navy", "sage", "amber"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBG.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        // Live icon preview
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.bereanProjectAccent(selectedColorKey).opacity(0.14))
                                .frame(width: 80, height: 80)
                            Image(systemName: icons[selectedIconIndex])
                                .font(.systemScaled(32, weight: .medium))
                                .foregroundStyle(Color.bereanProjectAccent(selectedColorKey))
                        }
                        .padding(.top, 12)
                        .animation(reduceMotion ? .none : .spring(response: 0.30, dampingFraction: 0.78), value: selectedColorKey)
                        .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78), value: selectedIconIndex)

                        // Colour strip
                        HStack(spacing: 12) {
                            ForEach(colorKeys, id: \.self) { key in
                                let isSelected = selectedColorKey == key
                                Circle()
                                    .fill(Color.bereanProjectAccent(key))
                                    .frame(width: isSelected ? 30 : 26, height: isSelected ? 30 : 26)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                isSelected ? Color.bereanProjectAccent(key) : .clear,
                                                lineWidth: 3
                                            )
                                            .scaleEffect(1.38)
                                    )
                                    .animation(reduceMotion ? .none : .spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
                                    .onTapGesture { withAnimation(reduceMotion ? nil : .default) { selectedColorKey = key } }
                            }
                        }

                        // Icon grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(icons.indices, id: \.self) { i in
                                let isSelected = selectedIconIndex == i
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected
                                              ? Color.bereanProjectAccent(selectedColorKey).opacity(0.14)
                                              : Color.bpCard)
                                    Image(systemName: icons[i])
                                        .font(.systemScaled(18, weight: .medium))
                                        .foregroundStyle(
                                            isSelected
                                            ? Color.bereanProjectAccent(selectedColorKey)
                                            : Color.bpSecondary
                                        )
                                }
                                .frame(height: 44)
                                .animation(reduceMotion ? .none : .spring(response: 0.26, dampingFraction: 0.78), value: isSelected)
                                .onTapGesture { withAnimation(reduceMotion ? nil : .default) { selectedIconIndex = i } }
                            }
                        }
                        .padding(.horizontal, 2)

                        fieldBlock(label: "PROJECT TITLE", placeholder: "e.g. Romans Study, Prayer Journal") {
                            TextField("", text: $title)
                                .font(.systemScaled(16)).focused($titleFocused)
                        }

                        fieldBlock(label: "DESCRIPTION (OPTIONAL)", placeholder: "What's this project about?") {
                            TextField("", text: $description, axis: .vertical)
                                .font(.systemScaled(15)).lineLimit(1...4)
                        }

                        Spacer().frame(height: 60)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.bpSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let project = BereanProject(
                            id: UUID(), title: t, iconSymbol: icons[selectedIconIndex],
                            colorKey: selectedColorKey,
                            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                            chatCount: 0, isPinned: false, memoryEnabled: true, lastUpdated: .now, folder: nil
                        )
                        onCreate(project)
                        dismiss()
                    }
                    .font(.systemScaled(15, weight: .semibold))
                    .foregroundStyle(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.bpTertiary
                        : Color.bereanProjectAccent(selectedColorKey)
                    )
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    @ViewBuilder
    private func fieldBlock<F: View>(
        label: String,
        placeholder: String,
        @ViewBuilder field: @escaping () -> F
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.systemScaled(11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Color.bpTertiary)
            field()
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bpCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.bpStroke, lineWidth: 0.5)
                        )
                )
        }
    }
}

// MARK: - Preview

struct BereanProjectsView_Previews: PreviewProvider {
    static var previews: some View {
        BereanProjectsView()
    }
}
