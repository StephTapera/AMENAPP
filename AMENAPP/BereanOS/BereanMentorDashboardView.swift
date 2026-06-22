// BereanMentorDashboardView.swift
// AMENAPP — Berean OS

import SwiftUI

struct BereanMentorDashboardView: View {
    @StateObject private var service = BereanMentorService.shared

    var body: some View {
        Group {
            if AMENFeatureFlags.shared.bereanOSMentorOSEnabled {
                mainContent
            } else {
                ContentUnavailableView(
                    "Mentorship",
                    systemImage: "person.2.fill",
                    description: Text("Coming soon")
                )
            }
        }
        .navigationTitle("Mentorship")
        .navigationBarTitleDisplayMode(.large)
        .task { try? await service.fetchMyMentorships() }
    }

    private var mainContent: some View {
        List(service.myMentorships) { relationship in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: relationship.mentorUid == nil ? "cpu.fill" : "person.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(relationship.mentorUid == nil ? "AI Mentor" : "Human Mentor")
                        .font(.headline)
                }
                Text(relationship.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
