// SpiritualInboxView.swift
// AMEN Hub — Unified Inbox
//
// The primary Hub (Unified Inbox) surface for the AMEN app.
// Wired to real Firestore via AmenHubRealtimeViewModel.
// Replaces the legacy spiritual-signals inbox as the Messages tab (tab 2) root.
//
// Glass rules:
//   • Filter bar: .regularMaterial — the ONLY glass surface
//   • List rows: plain background — no LiquidGlassCard on rows

import SwiftUI
import FirebaseAuth

// MARK: - SpiritualInboxView

struct SpiritualInboxView: View {
    @StateObject var viewModel = AmenHubRealtimeViewModel()
    @State private var selectedFilter: AmenHubItemType? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Filter bar (glass only here)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: selectedFilter == nil) {
                            selectedFilter = nil
                        }
                        ForEach(AmenHubItemType.allCases, id: \.self) { type in
                            FilterChip(title: type.label, isSelected: selectedFilter == type) {
                                selectedFilter = type
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(.regularMaterial)

                // MARK: Items list
                List {
                    let displayItems = viewModel.filteredItems(for: selectedFilter)
                    if displayItems.isEmpty && !viewModel.isLoading {
                        ContentUnavailableView(
                            "You're all caught up",
                            systemImage: "checkmark.circle",
                            description: Text("No \(selectedFilter?.label ?? "") items")
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(displayItems) { item in
                            HubItemRow(item: item)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        viewModel.prayForItem(itemId: item.id, title: item.title)
                                    } label: {
                                        Label("Pray", systemImage: "heart.fill")
                                    }
                                    .tint(.teal)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        viewModel.markAsRead(itemId: item.id)
                                    } label: {
                                        Label("Read", systemImage: "checkmark")
                                    }
                                    .tint(.blue)
                                }
                                .accessibilityLabel(
                                    "\(item.title) from \(item.senderName), \(item.timestamp.formatted(.relative(presentation: .named)))"
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Hub")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.unreadCount > 0 {
                        Text("\(viewModel.unreadCount) unread")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            if let uid = Auth.auth().currentUser?.uid {
                viewModel.startListening(uid: uid)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }
}

// MARK: - HubItemRow

struct HubItemRow: View {
    let item: AmenHubItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Unread dot
            Circle()
                .fill(item.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            // Avatar
            AsyncImage(url: URL(string: item.senderPhotoURL ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(item.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.senderName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Legacy Spiritual Inbox Support Views
// Kept for backward compatibility with SpiritualInboxSectionCard and SpiritualInboxThreadRow
// references throughout the codebase.

struct SpiritualInboxSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let count: Int
    @ViewBuilder let content: Content
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: { withAnimation(.spring(response: 0.35)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.1), in: Capsule())
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityLabel("\(title), \(count) items, \(isExpanded ? "expanded" : "collapsed")")

            if isExpanded {
                content
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 14, y: 5)
    }
}

struct SpiritualInboxThreadRow: View {
    let title: String
    let subtitle: String
    let flags: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.3))
                .frame(width: 3, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}
