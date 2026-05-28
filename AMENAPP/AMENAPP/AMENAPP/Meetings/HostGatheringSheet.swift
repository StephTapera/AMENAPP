import SwiftUI

// MARK: - HostGatheringSheet
// Liquid Glass sheet for hosting a new gathering in a group.
// Feeds into MeetingService.createMeeting — generalised from "Get Ready" church attendance.

struct HostGatheringSheet: View {
    let group: AmenGroup
    var onCreated: (Meeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var startAt = Date().addingTimeInterval(3600)
    @State private var studyPassage = ""
    @State private var locationName = ""
    @State private var agenda: [AgendaBlock] = []
    @State private var isCreating = false
    @State private var createError: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionLabel("Gathering Details", icon: "calendar")

                            styledTextField("Title", text: $title)

                            DatePicker("When", selection: $startAt, in: Date()...)
                                .font(.body)
                                .tint(AmenTheme.Colors.accentPrimary)

                            styledTextField("Location (optional)", text: $locationName)

                            styledTextField("Study passage, e.g. Romans 8:28 (optional)", text: $studyPassage)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                sectionLabel("Agenda", icon: "list.bullet.rectangle")
                                Spacer()
                                Button { addBlock() } label: {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(AmenTheme.Colors.accentPrimary)
                                }
                            }

                            if agenda.isEmpty {
                                Text("Tap + to add agenda items")
                                    .font(.caption)
                                    .foregroundStyle(AmenTheme.Colors.textTertiary)
                            } else {
                                ForEach($agenda) { $block in
                                    AgendaBlockRow(block: $block) {
                                        agenda.removeAll { $0.id == block.id }
                                    }
                                }
                                .onMove { agenda.move(fromOffsets: $0, toOffset: $1) }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Host a Gathering")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await create() } } label: {
                        if isCreating { ProgressView().scaleEffect(0.8) }
                        else { Text("Create").fontWeight(.semibold) }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .background(AmenTheme.Colors.backgroundPrimary)
            .alert("Couldn't Create Gathering", isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(createError ?? "Please try again.")
            }
        }
    }

    // MARK: - Helpers

    private func addBlock() {
        agenda.append(AgendaBlock(id: UUID().uuidString, type: .text, content: "", order: agenda.count))
    }

    private func create() async {
        guard let groupId = group.id else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let meeting = try await MeetingService.shared.createMeeting(
                groupId: groupId,
                title: title,
                startAt: startAt,
                locationName: locationName.isEmpty ? nil : locationName,
                studyPassage: studyPassage.isEmpty ? nil : studyPassage,
                agendaBlocks: agenda.enumerated().map { idx, b in
                    AgendaBlock(id: b.id, type: b.type, content: b.content, order: idx)
                }
            )
            onCreated(meeting)
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AmenTheme.Colors.textSecondary)
    }

    @ViewBuilder
    private func styledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.body)
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(10)
    }
}

// MARK: - Agenda Block Row

private struct AgendaBlockRow: View {
    @Binding var block: AgendaBlock
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AgendaBlockType.allCases, id: \.self) { type in
                    Button {
                        block.type = type
                    } label: {
                        Label(type.rawValue.capitalized, systemImage: type.systemImage)
                    }
                }
            } label: {
                Image(systemName: block.type.systemImage)
                    .font(.caption)
                    .foregroundStyle(AmenTheme.Colors.textSecondary)
                    .frame(width: 22)
            }

            TextField("Item", text: $block.content)
                .font(.subheadline)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AmenTheme.Colors.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - GlassCard

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AmenTheme.Colors.glassStroke, lineWidth: 0.5)
                    }
            }
    }
}
