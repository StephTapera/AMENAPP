// BereanRoomFirstEntrySheet.swift
// AMEN — Top-level entry point for Room Intelligence (BereanRoomFirst)
//
// Presents a brief explanation of the feature and directs the user to a
// Ministry Room, where BereanRoomFirstView activates automatically once
// there are enough messages (>=3 participants with human content).
//
// Flag gate: AMENFeatureFlags.shared.bereanRoomFirst
// Entry wired from HomeView toolbar menu (Study & Prayer section).

import SwiftUI

struct BereanRoomFirstEntrySheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        guard AMENFeatureFlags.shared.bereanRoomFirst else {
            return AnyView(EmptyView())
        }
        return AnyView(sheetContent)
    }

    private var sheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Spacer()
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What Room Intelligence Does")
                            .font(.headline)
                        Text("When a Ministry Room discussion has enough messages, Berean synthesizes what the room said — then adds a grounded biblical perspective. The human voice always appears first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where to Find It")
                            .font(.headline)
                        Text("Room Intelligence activates automatically inside any Ministry Room Discussions tab. Open a Spaces Ministry Room, tap the Discussions tab, and look for the synthesis banner.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Design Guarantee")
                            .font(.headline)
                        Text("Berean never speaks before the room does. The human summary is always rendered first — this order reflects the architecture and cannot be reversed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("Room Intelligence")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
