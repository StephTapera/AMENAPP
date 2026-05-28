// AmenIntegrationsHomeView.swift
// Integrations entry point — shown from Settings or Spaces actions
// Routes to Connected Apps, and contextually to Gatherings

import SwiftUI

struct AmenIntegrationsHomeView: View {
    @EnvironmentObject private var flags: AMENFeatureFlags
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                // Connected Apps section
                Section {
                    NavigationLink(destination: AmenIntegrationConnectionsView().environmentObject(flags)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected Apps")
                                    .font(.body)
                                Text("Microsoft 365, Zoom, Slack")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "puzzlepiece.extension.fill")
                                .foregroundStyle(.purple)
                        }
                    }
                    .accessibilityLabel("Connected Apps — Microsoft 365, Zoom, Slack")
                } header: {
                    Text("Integrations")
                } footer: {
                    Text("Connect external tools to coordinate gatherings, send reminders, and keep your ministry team informed.")
                }

                // Gatherings section — only shown when feature enabled
                if flags.amenGatheringsEnabled {
                    Section("Gatherings") {
                        NavigationLink(destination: AmenScheduleGatheringView().environmentObject(flags)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Schedule Gathering")
                                    Text("Create a prayer meeting, Bible study, or event")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundStyle(.blue)
                            }
                        }
                        NavigationLink(destination: AmenStartPrayerSessionView().environmentObject(flags)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Start Prayer Session")
                                    Text("Begin an immediate prayer call")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "hands.sparkles.fill")
                                    .foregroundStyle(.indigo)
                            }
                        }
                    }
                }

                // About section
                Section("About") {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privacy First")
                                .font(.subheadline.weight(.medium))
                            Text("AMEN never reads your email or stores meeting content without your permission.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Privacy First — AMEN never reads your email or stores meeting content without permission")
                }
            }
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    AmenIntegrationsHomeView()
        .environmentObject(AMENFeatureFlags.shared)
}
