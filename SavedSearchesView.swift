//
//  SavedSearchesView.swift
//  AMENAPP
//
//  Created by Steph on 1/29/26.
//

import SwiftUI

// MARK: - Saved Searches View

struct SavedSearchesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var savedSearchService = SavedSearchService.shared
    @State private var showingDeleteConfirmation = false
    @State private var searchToDelete: SavedSearch?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if savedSearchService.isLoading {
                    loadingView
                } else if savedSearchService.savedSearches.isEmpty {
                    emptyStateView
                } else {
                    searchListView
                }
            }
            .navigationTitle("Saved Searches")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert("Delete Saved Search?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let search = searchToDelete, let searchId = search.id {
                        Task {
                            try? await savedSearchService.deleteSavedSearch(id: searchId)
                        }
                    }
                }
            } message: {
                Text("This will also delete all alerts for this search.")
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading saved searches...")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 60)
            
            VStack(spacing: 12) {
                Text("No Saved Searches")
                    .font(.custom("OpenSans-Bold", size: 24))
                
                Text("Save searches to get alerts for new prayer requests, Bible studies, and more")
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Quick tips
            VStack(alignment: .leading, spacing: 16) {
                Text("How it works")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                SavedSearchTipRow(
                    icon: "magnifyingglass",
                    text: "Search for topics you care about"
                )
                SavedSearchTipRow(
                    icon: "bookmark.fill",
                    text: "Save the search for tracking"
                )
                SavedSearchTipRow(
                    icon: "bell.fill",
                    text: "Get notified of new results"
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6).opacity(0.5))
            )
            .padding(.horizontal, 32)
        }
    }
    
    // MARK: - Search List View
    
    private var searchListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Alert count badge
                if !savedSearchService.searchAlerts.filter({ !$0.isRead }).isEmpty {
                    alertBanner
                }
                
                // Saved searches
                ForEach(savedSearchService.savedSearches) { search in
                    SavedSearchCard(
                        search: search,
                        onToggleNotifications: {
                            if let searchId = search.id {
                                Task {
                                    try? await savedSearchService.toggleNotifications(searchId: searchId)
                                }
                            }
                        },
                        onDelete: {
                            searchToDelete = search
                            showingDeleteConfirmation = true
                        },
                        onTrigger: {
                            Task {
                                await savedSearchService.checkForNewResults(savedSearch: search)
                            }
                        }
                    )
                }
            }
            .padding(20)
        }
    }
    
    private var alertBanner: some View {
        let unreadCount = savedSearchService.searchAlerts.filter { !$0.isRead }.count
        
        return NavigationLink(destination: SearchAlertsView()) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(unreadCount) New Alert\(unreadCount == 1 ? "" : "s")")
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                    
                    Text("Tap to view your search notifications")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.1), .red.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.orange.opacity(0.3), .red.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Saved Search Card

struct SavedSearchCard: View {
    let search: SavedSearch
    let onToggleNotifications: () -> Void
    let onDelete: () -> Void
    let onTrigger: () -> Void
    
    @State private var isPressed = false
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: categoryIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Search info
                VStack(alignment: .leading, spacing: 6) {
                    Text(search.query)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if !search.filters.isEmpty {
                        Text(search.filters.joined(separator: ", "))
                            .font(.custom("OpenSans-Regular", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Notification badge
                if search.notificationsEnabled {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                }
            }
            
            // Stats
            HStack(spacing: 24) {
                SearchStatItem(
                    icon: "clock.fill",
                    value: relativeDate(search.createdAt),
                    label: "Created"
                )
                
                SearchStatItem(
                    icon: "arrow.clockwise",
                    value: "\(search.triggerCount)",
                    label: "Checks"
                )
                
                if let lastTriggered = search.lastTriggered {
                    SearchStatItem(
                        icon: "checkmark.circle.fill",
                        value: relativeDate(lastTriggered),
                        label: "Last check"
                    )
                }
            }
            
            Divider()
            
            // Actions
            HStack(spacing: 16) {
                // Notifications toggle
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onToggleNotifications()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: search.notificationsEnabled ? "bell.slash.fill" : "bell.fill")
                            .font(.system(size: 14))
                        Text(search.notificationsEnabled ? "Mute" : "Notify")
                            .font(.custom("OpenSans-Bold", size: 13))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                
                // Trigger check
                Button {
                    let haptic = UIImpactFeedbackGenerator(style: .light)
                    haptic.impactOccurred()
                    onTrigger()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                        Text("Check Now")
                            .font(.custom("OpenSans-Bold", size: 13))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.1))
                    )
                }
                
                Spacer()
                
                // Delete
                Button {
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.warning)
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }
    
    private var categoryIcon: String {
        if search.query.contains("prayer") || search.query.contains("pray") {
            return "hands.sparkles.fill"
        } else if search.query.contains("bible") {
            return "book.closed.fill"
        } else if search.query.contains("testimony") {
            return "star.fill"
        } else if search.query.contains("group") {
            return "person.3.fill"
        } else {
            return "magnifyingglass"
        }
    }
    
    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct SearchStatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
            }
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SavedSearchTipRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Search Alerts View

struct SearchAlertsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var savedSearchService = SavedSearchService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if savedSearchService.searchAlerts.isEmpty {
                    emptyAlertsView
                } else {
                    ForEach(savedSearchService.searchAlerts) { alert in
                        SearchAlertCard(alert: alert) {
                            Task {
                                try? await savedSearchService.markAlertAsRead(alertId: alert.id!)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Search Alerts")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var emptyAlertsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding(.top, 60)
            
            Text("No Alerts Yet")
                .font(.custom("OpenSans-Bold", size: 20))
            
            Text("You'll be notified when there are new results for your saved searches")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SearchAlertCard: View {
    let alert: SearchAlert
    let onMarkAsRead: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(alert.query)
                        .font(.custom("OpenSans-Bold", size: 17))
                        .foregroundStyle(.primary)
                    
                    Text("\(alert.resultCount) new result\(alert.resultCount == 1 ? "" : "s")")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !alert.isRead {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                }
            }
            
            Text(alert.createdAt, style: .relative)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.tertiary)
            
            if !alert.isRead {
                Button {
                    onMarkAsRead()
                } label: {
                    Text("Mark as Read")
                        .font(.custom("OpenSans-Bold", size: 13))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.1))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(alert.isRead ? Color(.systemBackground) : Color.orange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(alert.isRead ? Color.clear : Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview
#Preview {
    SavedSearchesView()
}
