// BereanMemoryInspectView.swift
// AMENAPP — Berean Spiritual Intelligence Layer (Wave 3)
//
// User-facing memory inspection and deletion surface.
// - Zone badges: .preference → green, .sensitive → amber, .high → red.
// - High-zone values are blurred until the user taps to reveal.
// - "Delete All Memory" requires confirmation.
//
// Guard: if bereanSpiritualMemoryEnabled is false, renders ContentUnavailableView.

import SwiftUI

struct BereanMemoryInspectView: View {

    @StateObject private var store = BereanMemoryStore.shared
    @State private var revealedFields: Set<MemoryField> = []
    @State private var showDeleteAllAlert = false

    var body: some View {
        Group {
            if !AMENFeatureFlags.shared.bereanSpiritualMemoryEnabled {
                ContentUnavailableView(
                    "Memory is not enabled",
                    systemImage: "brain",
                    description: Text("Berean Spiritual Memory has not been activated for your account.")
                )
            } else {
                contentList
            }
        }
        .navigationTitle("Berean Memory")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Content List

    private var contentList: some View {
        List {
            headerSection
            fieldsSection
            deleteAllSection
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemBackground))
        .alert("Delete All Memory?", isPresented: $showDeleteAllAlert) {
            Button("Delete All", role: .destructive) {
                store.deleteAll()
                revealedFields.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All Berean memory — including prayer history — will be permanently erased. This cannot be undone.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("What Berean Remembers")
                    .font(.headline)
                Text("Berean stores a small set of spiritual preferences to personalise your study experience. High-sensitivity fields like prayer history are encrypted on your device and never leave it in readable form.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Fields Section

    private var fieldsSection: some View {
        Section("Stored Fields") {
            ForEach(MemoryField.allCases, id: \.self) { field in
                MemoryFieldRow(
                    field: field,
                    currentValue: store.value(for: field),
                    isRevealed: revealedFields.contains(field),
                    onToggleReveal: {
                        if revealedFields.contains(field) {
                            revealedFields.remove(field)
                        } else {
                            revealedFields.insert(field)
                        }
                    },
                    onDelete: {
                        store.delete(field: field)
                        revealedFields.remove(field)
                    }
                )
            }
        }
    }

    // MARK: - Delete All Section

    private var deleteAllSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteAllAlert = true
            } label: {
                Label("Delete All Memory", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - MemoryFieldRow

private struct MemoryFieldRow: View {

    let field: MemoryField
    let currentValue: String?
    let isRevealed: Bool
    let onToggleReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(fieldDisplayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.label))

                ZoneBadge(zone: field.zone)

                Spacer()

                if currentValue != nil {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Delete \(fieldDisplayName)")
                }
            }

            if let value = currentValue {
                if field.zone == .high && !isRevealed {
                    // Blurred high-zone value with tap to reveal
                    Button(action: onToggleReveal) {
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .blur(radius: 4)
                            .overlay(
                                Text("Tap to reveal")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.blue)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hidden value. Tap to reveal.")
                } else {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .onTapGesture {
                            if field.zone == .high { onToggleReveal() }
                        }
                }
            } else {
                Text("Not set")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .italic()
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(.systemBackground))
    }

    private var fieldDisplayName: String {
        switch field {
        case .preferredTranslation: return "Preferred Translation"
        case .studyStyle:           return "Study Style"
        case .theologicalLean:      return "Theological Lean"
        case .denominationalLean:   return "Denominational Lean"
        case .readingHabits:        return "Reading Habits"
        case .prayerHistory:        return "Prayer History"
        }
    }
}

// MARK: - ZoneBadge

private struct ZoneBadge: View {

    let zone: PrivacyCoreZone

    var body: some View {
        Text(zoneName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(zoneColor, in: Capsule())
    }

    private var zoneName: String {
        switch zone {
        case .preference:  return "Preference"
        case .behavioral:  return "Behavioral"
        case .sensitive:   return "Sensitive"
        case .high:        return "Encrypted"
        case .public:      return "Public"
        case .functional:  return "Functional"
        case .identity:    return "Identity"
        }
    }

    private var zoneColor: Color {
        switch zone {
        case .preference:  return .green
        case .behavioral:  return Color(red: 0.3, green: 0.6, blue: 0.3)
        case .sensitive:   return .orange
        case .high:        return .red
        case .public:      return .gray
        case .functional:  return .gray
        case .identity:    return .purple
        }
    }
}
