// BereanAgentWorkspacesView.swift
// AMEN — Berean Agent Surface · Wave 3 Lane F
//
// Main workspaces hub with tab taxonomy and create-workspace sheet.
// Design §2: Liquid Glass (.glassEffect()), warm paper bg, tan surface,
//             wine-red accent (one element per screen max), 24pt corners,
//             soft shadow (radius 12, opacity 0.12).
// §7: isEncrypted = false always. E2EE badge only shown when true (never in this build).
//     bereanAgentWorkspacesEnabled flag guards Firestore writes (stubbed).
// Accessibility: Dynamic Type, VoiceOver labels on all interactive elements,
//                @Environment(\.accessibilityReduceMotion) guard on all animations.

import SwiftUI

// MARK: - BASWorkspace Stubs

private extension BASWorkspace {
    static var stubs: [BASWorkspace] {
        [
            BASWorkspace(
                id: "ws-001",
                name: "Sunday Morning Bible Study",
                role: .owner,
                tab: .bibleStudies,
                isPrivate: false,
                createdBy: "you",
                memberCount: 12,
                isEncrypted: false
            ),
            BASWorkspace(
                id: "ws-002",
                name: "Pastoral Team Sermons",
                role: .pastorAdmin,
                tab: .sermons,
                isPrivate: true,
                createdBy: "pastor",
                memberCount: 5,
                isEncrypted: false
            ),
            BASWorkspace(
                id: "ws-003",
                name: "Women's Prayer Circle",
                role: .contributor,
                tab: .prayerGroups,
                isPrivate: false,
                createdBy: "sarah",
                memberCount: 28,
                isEncrypted: false
            ),
            BASWorkspace(
                id: "ws-004",
                name: "Morning Devotionals",
                role: .viewer,
                tab: .devotionals,
                isPrivate: false,
                createdBy: "deacon",
                memberCount: 104,
                isEncrypted: false
            ),
            BASWorkspace(
                id: "ws-005",
                name: "Church Community Updates",
                role: .prayerOnly,
                tab: .church,
                isPrivate: false,
                createdBy: "admin",
                memberCount: 340,
                isEncrypted: false
            )
        ]
    }
}

// MARK: - Main View

@MainActor
struct BereanAgentWorkspacesView: View {

    @State private var selectedTab: BASWorkspaceTab = .allContent
    @State private var showCreate: Bool = false
    @State private var workspaces: [BASWorkspace] = BASWorkspace.stubs

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Filtered workspaces for the current tab
    private var filteredWorkspaces: [BASWorkspace] {
        switch selectedTab {
        case .allContent:
            return workspaces
        case .createdByYou:
            return workspaces.filter { $0.createdBy == "you" }
        case .sharedWithYou:
            return workspaces.filter { $0.role != .owner }
        case .church:
            return workspaces.filter { $0.tab == .church }
        case .bibleStudies:
            return workspaces.filter { $0.tab == .bibleStudies }
        case .sermons:
            return workspaces.filter { $0.tab == .sermons }
        case .prayerGroups:
            return workspaces.filter { $0.tab == .prayerGroups }
        case .devotionals:
            return workspaces.filter { $0.tab == .devotionals }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.basWarmPaper
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Tab chip row
                    tabChipRow
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    // Workspace list
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            if filteredWorkspaces.isEmpty {
                                emptyState
                                    .padding(.top, 40)
                            } else {
                                ForEach(filteredWorkspaces) { workspace in
                                    BASWorkspaceCard(workspace: workspace)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Workspaces")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(
                            reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                        ) {
                            showCreate = true
                        }
                    } label: {
                        Label("New Workspace", systemImage: "plus.circle")
                            .foregroundStyle(Color.basWineRed)
                    }
                    .accessibilityLabel("New Workspace")
                }
            }
            .sheet(isPresented: $showCreate) {
                BASCreateWorkspaceSheet { newWorkspace in
                    withAnimation(
                        reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                    ) {
                        workspaces.insert(newWorkspace, at: 0)
                    }
                    showCreate = false
                } onCancel: {
                    showCreate = false
                }
            }
        }
    }

    // MARK: Tab Chip Row

    private var tabChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BASWorkspaceTab.allCases) { tab in
                    let isSelected = tab == selectedTab
                    Button {
                        withAnimation(
                            reduceMotion ? .none : Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))
                        ) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.displayName)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? Color.basWineRed : Color.basInk)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected
                                    ? Color.basWineRed.opacity(0.1)
                                    : Color.basTan.opacity(0.6),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        isSelected ? Color.basWineRed : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .accessibilityLabel("\(tab.displayName), \(isSelected ? "selected" : "")")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(Color.basInk.opacity(0.25))
                .accessibilityHidden(true)
            Text("No items in this workspace yet.")
                .font(.subheadline)
                .foregroundStyle(Color.basInk.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No items in this workspace yet.")
    }
}

// MARK: - Workspace Card

@MainActor
private struct BASWorkspaceCard: View {

    let workspace: BASWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            Text(workspace.name)
                .font(.headline)
                .foregroundStyle(Color.basInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Role chip
            roleChip

            // Footer row: lock + member count + chevron
            HStack(spacing: 6) {
                if workspace.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.basInk.opacity(0.55))
                        .accessibilityHidden(true)
                }

                Text("\(workspace.memberCount) members")
                    .font(.caption)
                    .foregroundStyle(Color.basInk.opacity(0.55))

                Spacer()

                // E2EE badge — §7: isEncrypted is always false in this build;
                // badge shown only if true (never displayed here)
                if workspace.isEncrypted {
                    Text("E2EE: Coming Soon")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.basInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.25), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1))
                        .accessibilityLabel("End-to-end encryption: Coming Soon")
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.basInk.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .padding(18)
        .background(
            Color.basWarmPaper,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.basTan, lineWidth: 1)
        )
        .shadow(color: Color.basInk.opacity(0.12), radius: 12, x: 0, y: 4)
        .glassEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workspace.name), \(workspace.role.accessibilityLabel), \(workspace.memberCount) members")
    }

    // MARK: Role Chip

    private var roleChip: some View {
        Text(workspace.role.chipLabel)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(workspace.role.chipForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(workspace.role.chipBackground, in: Capsule())
            .accessibilityLabel("Role: \(workspace.role.chipLabel)")
    }
}

// MARK: - Role Display Helpers

private extension BASWorkspaceRole {
    var chipLabel: String {
        switch self {
        case .owner:        return "Owner"
        case .pastorAdmin:  return "Pastor / Admin"
        case .contributor:  return "Contributor"
        case .viewer:       return "Viewer"
        case .prayerOnly:   return "Prayer Only"
        }
    }

    var chipForeground: Color {
        switch self {
        case .owner:        return Color.basWineRed
        case .pastorAdmin:  return Color(hex: "92400E")   // amber-800-equivalent
        case .contributor:  return Color.secondary
        case .viewer:       return Color.secondary
        case .prayerOnly:   return Color.secondary
        }
    }

    var chipBackground: Color {
        switch self {
        case .owner:        return Color.basWineRed.opacity(0.12)
        case .pastorAdmin:  return Color(hex: "FDE68A").opacity(0.45)  // amber tint
        case .contributor:  return Color.basTan.opacity(0.7)
        case .viewer:       return Color.basTan.opacity(0.55)
        case .prayerOnly:   return Color.basTan.opacity(0.55)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .owner:        return "Owner"
        case .pastorAdmin:  return "Pastor or Admin"
        case .contributor:  return "Contributor"
        case .viewer:       return "Viewer"
        case .prayerOnly:   return "Prayer Only"
        }
    }
}

// MARK: - Create Workspace Sheet

@MainActor
private struct BASCreateWorkspaceSheet: View {

    var onCreate: (BASWorkspace) -> Void
    var onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedType: BASWorkspaceTab = .allContent
    @State private var isPrivate: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.basWarmPaper.ignoresSafeArea()

                Form {
                    Section("Workspace Details") {
                        TextField("Workspace name", text: $name)
                            .accessibilityLabel("Workspace name")

                        Picker("Type", selection: $selectedType) {
                            ForEach(BASWorkspaceTab.allCases) { tab in
                                Text(tab.displayName).tag(tab)
                            }
                        }
                        .accessibilityLabel("Workspace type")

                        Toggle("Private", isOn: $isPrivate)
                            .tint(Color.basWineRed)
                            .accessibilityLabel("Private workspace")
                    }

                    // §7: isEncrypted = false always — no UI control exposed
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        withAnimation(
                            reduceMotion ? .none : Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.8))
                        ) {
                            onCancel()
                        }
                    }
                    .foregroundStyle(Color.basInk)
                    .accessibilityLabel("Cancel creating workspace")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        guard isValid else { return }
                        // §7: bereanAgentWorkspacesEnabled flag guards Firestore path
                        // bereanWorkspaces/{uid}/workspaces/{id} — stubbed here
                        let newWorkspace = BASWorkspace(
                            id: UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespaces),
                            role: .owner,
                            tab: selectedType,
                            isPrivate: isPrivate,
                            createdBy: "you",
                            memberCount: 1,
                            isEncrypted: false  // §7: always false
                        )
                        withAnimation(
                            reduceMotion ? .none : Motion.adaptive(.spring(response: 0.4, dampingFraction: 0.8))
                        ) {
                            onCreate(newWorkspace)
                        }
                    }
                    .foregroundStyle(isValid ? Color.basWineRed : Color.secondary)
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                    .accessibilityLabel("Create workspace")
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Workspaces Hub") {
    BereanAgentWorkspacesView()
}

#Preview("Create Sheet") {
    BASCreateWorkspaceSheet(
        onCreate: { ws in print("Created: \(ws.name)") },
        onCancel: { print("Cancelled") }
    )
}
#endif
