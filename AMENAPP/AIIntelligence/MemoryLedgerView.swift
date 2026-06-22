// MemoryLedgerView.swift
// AMENAPP
//
// Wave 3 — the Memory Ledger + Data Vault surface. Lists the real on-device
// Berean memory (why it was stored, when, the PRIVACY-CORE zone) with working
// delete-per-entry, pause, export-everything, and delete-everything controls.
// Every control acts on the real store via MemoryLedgerService (§2.6).
//
// Gated by AMENFeatureFlags.shared.memoryLedgerEnabled (default OFF).

import SwiftUI

struct MemoryLedgerView: View {
    @StateObject private var service = MemoryLedgerService()
    @State private var paused = false
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            pauseSection

            if service.entries.isEmpty {
                Section {
                    Text("Berean isn't remembering anything about you right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("What Berean remembers") {
                    ForEach(service.entries) { entry in
                        MemoryEntryRow(entry: entry)
                            .swipeActions {
                                if entry.deletable {
                                    Button(role: .destructive) {
                                        service.delete(entry)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
            }

            dataVaultSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Berean Memory")
        .onAppear {
            paused = service.isPaused
            service.reload()
        }
        .confirmationDialog(
            "Delete all Berean memory?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { service.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes everything Berean remembers about you on this device. This cannot be undone.")
        }
    }

    private var pauseSection: some View {
        Section {
            Toggle(isOn: $paused) {
                Label("Pause memory", systemImage: "pause.circle")
            }
            .tint(.blue)
            .onChange(of: paused) { _, newValue in
                service.isPaused = newValue
            }
        } footer: {
            Text("When paused, Berean stops saving anything new. Existing memory stays until you delete it.")
        }
    }

    private var dataVaultSection: some View {
        Section("Your data") {
            ShareLink(item: service.exportJSON()) {
                Label("Export everything", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)

            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Label("Delete all my memory", systemImage: "trash")
            }
            .disabled(service.entries.isEmpty)
        }
    }
}

// MARK: - Row

private struct MemoryEntryRow: View {
    let entry: MemoryLedgerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.summary)
                .font(.subheadline.weight(.medium))
            Text(entry.whyStored)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Label(zoneLabel, systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                // Honest: the store does not track usage — say so, don't fake a count.
                Text("Usage not tracked")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var zoneLabel: String {
        entry.namespace.replacingOccurrences(of: "device:", with: "").capitalized
    }
}

#if DEBUG
#Preview("Memory ledger") {
    NavigationStack { MemoryLedgerView() }
}
#endif
