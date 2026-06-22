import SwiftUI

// MARK: - AmenAudioAttachmentDraft

struct AmenAudioAttachmentDraft: Equatable {
    enum Category: String, CaseIterable {
        case worship
        case instrumental
        case sermonClips = "sermon_clips"
        case prayer
        case testimony
        case ambient
        case originalAudio = "original_audio"
        case savedApproved = "saved_approved"
    }

    let title: String
    let artist: String
    let source: String
    let category: Category
    let trimStartMs: Int
    let trimDurationMs: Int
    let musicVolume: Double
    let originalAudioVolume: Double
    let isApproved: Bool

    /// Returns a media audio bed metadata dict if the draft is approved.
    var asMediaAudioBed: (title: String, source: String)? {
        guard isApproved else { return nil }
        return (title: title, source: source)
    }
}

struct AmenAudioComposerSheet: View {
    private struct AmenAudioPreset: Identifiable {
        let id = UUID()
        let title: String
        let artist: String
        let source: String
        let category: AmenAudioAttachmentDraft.Category
    }

    private static let presets: [AmenAudioPreset] = [
        .init(title: "Be Still (Instrumental)", artist: "Amen Library", source: "approved_catalog", category: .instrumental),
        .init(title: "Morning Prayer Pad", artist: "Amen Library", source: "approved_catalog", category: .prayer),
        .init(title: "Worship Atmosphere", artist: "Amen Library", source: "approved_catalog", category: .worship),
        .init(title: "Sermon Underscore", artist: "Amen Library", source: "approved_catalog", category: .sermonClips),
        .init(title: "Testimony Bed", artist: "Amen Library", source: "approved_catalog", category: .testimony),
        .init(title: "Quiet Ambient", artist: "Amen Library", source: "approved_catalog", category: .ambient)
    ]

    let draft: AmenAudioAttachmentDraft?
    let onCancel: () -> Void
    let onApply: (AmenAudioAttachmentDraft) -> Void

    @State private var selectedCategory: AmenAudioAttachmentDraft.Category
    @State private var selectedPresetID: UUID?
    @State private var trimStartMs: Int
    @State private var trimDurationMs: Int
    @State private var musicVolume: Double
    @State private var originalAudioVolume: Double

    init(
        draft: AmenAudioAttachmentDraft?,
        onCancel: @escaping () -> Void,
        onApply: @escaping (AmenAudioAttachmentDraft) -> Void
    ) {
        self.draft = draft
        self.onCancel = onCancel
        self.onApply = onApply

        _selectedCategory = State(initialValue: draft?.category ?? .worship)
        _trimStartMs = State(initialValue: draft?.trimStartMs ?? 0)
        _trimDurationMs = State(initialValue: draft?.trimDurationMs ?? 15000)
        _musicVolume = State(initialValue: draft?.musicVolume ?? 0.35)
        _originalAudioVolume = State(initialValue: draft?.originalAudioVolume ?? 0.7)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Approved Amen audio only. Public reuse requires approved tracks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    categoryChips

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose audio")
                            .font(.subheadline.weight(.semibold))
                        ForEach(filteredPresets) { preset in
                            Button {
                                selectedPresetID = preset.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(preset.artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selectedPresetID == preset.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedPresetID == preset.id ? .primary : .secondary)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trim")
                            .font(.subheadline.weight(.semibold))
                        LabeledContent("Start", value: "\(trimStartMs / 1000)s")
                        Slider(value: Binding(get: { Double(trimStartMs) }, set: { trimStartMs = Int($0) }), in: 0...30000, step: 500)
                        LabeledContent("Duration", value: "\(trimDurationMs / 1000)s")
                        Slider(value: Binding(get: { Double(trimDurationMs) }, set: { trimDurationMs = Int($0) }), in: 5000...30000, step: 500)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mix")
                            .font(.subheadline.weight(.semibold))
                        LabeledContent("Music", value: "\(Int(musicVolume * 100))%")
                        Slider(value: $musicVolume, in: 0...1)
                        LabeledContent("Original Audio", value: "\(Int(originalAudioVolume * 100))%")
                        Slider(value: $originalAudioVolume, in: 0...1)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("Add Music")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("amen_audio_composer_sheet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("amen_audio_composer_cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        guard let preset = selectedPreset else { return }
                        onApply(
                            AmenAudioAttachmentDraft(
                                title: preset.title,
                                artist: preset.artist,
                                source: preset.source,
                                category: preset.category,
                                trimStartMs: trimStartMs,
                                trimDurationMs: trimDurationMs,
                                musicVolume: musicVolume,
                                originalAudioVolume: originalAudioVolume,
                                isApproved: true
                            )
                        )
                    }
                    .disabled(selectedPreset == nil)
                    .accessibilityIdentifier("amen_audio_composer_apply")
                }
            }
        }
    }

    private var filteredPresets: [AmenAudioPreset] {
        Self.presets.filter { $0.category == selectedCategory }
    }

    private var selectedPreset: AmenAudioPreset? {
        filteredPresets.first { $0.id == selectedPresetID } ?? filteredPresets.first
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AmenAudioAttachmentDraft.Category.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = category
                        selectedPresetID = filteredPresets.first?.id
                    } label: {
                        Text(label(for: category))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selectedCategory == category ? Color.black : Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("amen_audio_category_\(category.rawValue)")
                }
            }
        }
    }

    private func label(for category: AmenAudioAttachmentDraft.Category) -> String {
        switch category {
        case .worship: return "Worship"
        case .instrumental: return "Instrumental"
        case .sermonClips: return "Sermon Clips"
        case .prayer: return "Prayer"
        case .testimony: return "Testimony"
        case .ambient: return "Ambient"
        case .originalAudio: return "Original"
        case .savedApproved: return "Saved"
        }
    }
}
