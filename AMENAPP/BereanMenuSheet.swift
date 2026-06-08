// BereanMenuSheet.swift
// AMEN App — Berean sidebar menu.
//
// Design reference: ChatGPT sidebar (IMG_2397) · translated to AMEN Liquid Glass.
// Layout: header (title + search + X) · quick modes · pinned sessions · recents · New Chat CTA.
// Presented as .sheet — draggable, large detent, ultraThinMaterial background.

import SwiftUI
import FirebaseAuth

// MARK: - BereanMenuSheet

struct BereanMenuSheet: View {

    @Binding var isPresented: Bool
    let onNewChat: () -> Void
    let onSelectSession: (BereanChatSession) -> Void

    @StateObject private var sessionManager = BereanChatSessionManager.shared
    @State private var searchText = ""
    @State private var showSearchField = false
    @State private var showAllModes = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let bgColor = Color(red: 0.971, green: 0.971, blue: 0.969)

    // MARK: - Derived

    private var filteredSessions: [BereanChatSession] {
        guard !searchText.isEmpty else { return sessionManager.sessions }
        return sessionManager.sessions.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var pinnedSessions: [BereanChatSession] {
        Array(filteredSessions.prefix(3))
    }

    private var recentSessions: [BereanChatSession] {
        filteredSessions.count > 3 ? Array(filteredSessions.dropFirst(3)) : []
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background
                (reduceTransparency ? bgColor : Color.clear)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        // Search field (conditional)
                        if showSearchField {
                            searchField
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 4)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Quick modes
                        quickModesSection
                            .padding(.top, 8)

                        // Pinned sessions
                        if !pinnedSessions.isEmpty {
                            sectionLabel("Pinned")
                            ForEach(pinnedSessions) { session in
                                sessionRow(session, icon: "folder")
                            }
                        }

                        // Recents
                        if !recentSessions.isEmpty {
                            sectionLabel("Recents")
                            ForEach(recentSessions) { session in
                                sessionRow(session, icon: "bubble.left")
                            }
                        }

                        // Empty state
                        if sessionManager.sessions.isEmpty {
                            emptySessionsHint
                                .padding(.top, 32)
                        }

                        // Clearance for pinned button
                        Spacer().frame(height: 110)
                    }
                }

                // Pinned "New Chat" button — always visible
                newChatButton
                    .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { headerTitle }
                ToolbarItem(placement: .topBarTrailing) { trailingButtons }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? AnyShapeStyle(bgColor) : AnyShapeStyle(.ultraThinMaterial))
        .sheet(isPresented: $showAllModes) {
            BereanAllModesSheet(isPresented: $showAllModes, onSelect: { mode in
                showAllModes = false
                NotificationCenter.default.post(name: Notification.Name("amenBereanModeSelected"), object: mode)
                triggerNewChat()
            })
        }
    }

    // MARK: - Toolbar

    private var headerTitle: some View {
        HStack(spacing: 7) {
            Image(systemName: "graduationcap")
                .font(.systemScaled(14, weight: .medium))
                .foregroundColor(.black.opacity(0.62))
            Text("Berean")
                .font(.systemScaled(17, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }

    private var trailingButtons: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    showSearchField.toggle()
                    if !showSearchField { searchText = "" }
                }
            } label: {
                glassCircleIcon("magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search conversations")

            Button { isPresented = false } label: {
                glassCircleIcon("xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close menu")
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.systemScaled(14, weight: .regular))
                .foregroundColor(.secondary)
            TextField("Search conversations", text: $searchText)
                .font(.systemScaled(15))
                .foregroundColor(.primary)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.systemScaled(14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(glassCard(radius: 12))
    }

    // MARK: - Quick modes

    private var quickModesSection: some View {
        VStack(spacing: 0) {
            quickModeRow(icon: "book.pages",        label: "Scripture Study",  action: { triggerNewChat() })
            quickModeRow(icon: "hands.sparkles",    label: "Prayer",           action: { triggerNewChat() })
            quickModeRow(icon: "note.text",         label: "Church Notes",     action: { triggerNewChat() })
            quickModeRow(icon: "ellipsis",          label: "More",             action: { showAllModes = true })
        }
        .padding(.horizontal, 16)
    }

    private func quickModeRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(16, weight: .medium))
                    .foregroundColor(.black.opacity(0.68))
                    .frame(width: 22)
                Text(label)
                    .font(.systemScaled(16, weight: .regular))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.systemScaled(13, weight: .semibold))
            .foregroundColor(.black.opacity(0.42))
            .padding(.horizontal, 30)
            .padding(.top, 22)
            .padding(.bottom, 4)
    }

    // MARK: - Session row

    private func sessionRow(_ session: BereanChatSession, icon: String) -> some View {
        Button {
            sessionManager.activate(session.id)
            isPresented = false
            onSelectSession(session)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundColor(.black.opacity(0.48))
                    .frame(width: 20)
                Text(session.displayTitle)
                    .font(.systemScaled(15, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptySessionsHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.systemScaled(28, weight: .light))
                .foregroundColor(.black.opacity(0.28))
            Text("No conversations yet.\nTap New Chat to get started.")
                .font(.systemScaled(14))
                .foregroundColor(.black.opacity(0.42))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - New Chat button

    private var newChatButton: some View {
        Button {
            triggerNewChat()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.systemScaled(15, weight: .semibold))
                Text("New Chat")
                    .font(.systemScaled(15, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.20), radius: 14, y: 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start new Berean conversation")
    }

    // MARK: - Helpers

    private func triggerNewChat() {
        isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onNewChat()
        }
    }

    private func glassCircleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.systemScaled(14, weight: .semibold))
            .foregroundColor(.black.opacity(0.72))
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(Circle().fill(Color.white.opacity(0.52)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
    }

    private func glassCard(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(reduceTransparency ? Color(.systemBackground) : Color.clear)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.60))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
            )
    }
}

// MARK: - BereanAllModesSheet

private struct BereanAllModesSheet: View {
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    private let modes: [(icon: String, label: String, mode: String)] = [
        ("book.pages",        "Scripture Study",    "scripture"),
        ("hands.sparkles",    "Prayer",             "prayer"),
        ("note.text",         "Church Notes",       "church_notes"),
        ("lightbulb",         "Wisdom",             "wisdom"),
        ("magnifyingglass",   "Research",           "research"),
        ("chart.bar.doc.horizontal", "Debate",      "debate"),
        ("person.2",          "Multi-Perspective",  "multi_perspective"),
        ("brain.head.profile","Deep Study",         "deep_study"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(modes, id: \.mode) { item in
                    Button {
                        onSelect(item.mode)
                    } label: {
                        Label(item.label, systemImage: item.icon)
                            .font(.body)
                    }
                }
            }
            .navigationTitle("All Modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
