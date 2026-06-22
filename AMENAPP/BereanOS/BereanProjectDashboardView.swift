// BereanProjectDashboardView.swift
// AMENAPP — Berean OS

import SwiftUI

struct BereanProjectDashboardView: View {
    @StateObject private var service = BereanProjectService.shared
    @State private var showCreate = false

    var body: some View {
        List {
            ForEach(service.projects) { project in
                BereanProjectCardView(project: project)
            }
        }
        .navigationTitle("My Projects")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { try? await service.fetchProjects() }
    }
}
