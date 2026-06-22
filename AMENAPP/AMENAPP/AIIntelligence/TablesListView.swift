// TablesListView.swift
// AMEN — Tables hub: lists the user's joined Tables
//
// Flag-gated: AMENFeatureFlags.shared.tables
// Entry point wired from HomeView toolbar menu (Study & Prayer section).

import SwiftUI
import FirebaseAuth

struct TablesListView: View {

    @StateObject private var service = TableService()
    @State private var tables: [Table] = []
    @State private var loadError: String?
    @State private var isLoading = true

    private var uid: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if !AMENFeatureFlags.shared.tables {
                    ContentUnavailableView(
                        "Tables Coming Soon",
                        systemImage: "rectangle.3.group.fill",
                        description: Text("Small-group study and discussion Tables will be available soon.")
                    )
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    ContentUnavailableView(
                        "Couldn't Load Tables",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if tables.isEmpty {
                    ContentUnavailableView(
                        "No Tables Yet",
                        systemImage: "rectangle.3.group.fill",
                        description: Text("Join a Table anchored in scripture, a season, or a shared topic.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(tables) { table in
                                TableCardView(
                                    table: table,
                                    currentUid: uid,
                                    displayNames: [:],
                                    onJoin: {
                                        try await service.joinTable(tableId: table.id, uid: uid)
                                    },
                                    onLeave: {
                                        try await service.leaveTable(tableId: table.id, uid: uid)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .navigationTitle("Tables")
            .navigationBarTitleDisplayMode(.large)
            .task {
                guard AMENFeatureFlags.shared.tables, !uid.isEmpty else {
                    isLoading = false
                    return
                }
                do {
                    for try await batch in service.myTables(for: uid) {
                        tables = batch
                        isLoading = false
                    }
                } catch {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
