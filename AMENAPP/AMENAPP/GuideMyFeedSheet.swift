import SwiftUI

struct GuideMyFeedSheet: View {
    @Binding var draft: FeedDirectionDraft
    let onApply: (FeedDirectionDraft) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    detectedSection
                    previewSection
                    visibilitySection
                    durationSection
                    intensitySection
                    surfacesSection
                    transparencyNote
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle("Guide your feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(reduceTransparency ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(Material.regularMaterial))
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 8)
            Text("Tell Amen what to show more or less of. You stay in control.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Detected request")
            Text(draft.interpretedSummary ?? draft.rawText)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var previewSection: some View {
        FeedDirectionPreviewView(draft: draft)
    }

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Privacy")
            HStack(spacing: 10) {
                ForEach([FeedDirectionVisibility.privateOnly, .applyAndPost], id: \.self) { option in
                    visibilityPill(option)
                }
                Spacer()
            }
            Text(draft.visibility == .privateOnly
                 ? "Updates your feed only. Nothing is posted."
                 : "Updates your feed and shares this publicly.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibilityPill(_ option: FeedDirectionVisibility) -> some View {
        let isSelected = draft.visibility == option
        let label = option == .privateOnly ? "Private only" : "Apply + Post"
        let icon = option == .privateOnly ? "lock" : "globe"
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                draft.visibility = option
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? Color.primary.opacity(0.09) : Color(.secondarySystemBackground))
                    .overlay(Capsule().stroke(Color.black.opacity(isSelected ? 0.12 : 0.06), lineWidth: 0.8))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Duration")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FeedDirectionDuration.allCases, id: \.self) { d in
                        selectionPill(label: d.displayName, isSelected: draft.duration == d) {
                            draft.duration = d
                        }
                    }
                }
            }
        }
    }

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Strength")
            HStack(spacing: 8) {
                ForEach(FeedDirectionIntensity.allCases, id: \.self) { i in
                    selectionPill(label: i.displayName, isSelected: draft.intensity == i) {
                        draft.intensity = i
                    }
                }
                Spacer()
            }
        }
    }

    private var surfacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Applies to")
            AMENFlowLayout(spacing: 8) {
                ForEach(FeedSurface.allCases, id: \.self) { surface in
                    let isOn = draft.affectedSurfaces.contains(surface)
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                            if isOn {
                                draft.affectedSurfaces.removeAll { $0 == surface }
                            } else {
                                draft.affectedSurfaces.append(surface)
                            }
                        }
                    } label: {
                        Label(surface.displayName, systemImage: surface.icon)
                            .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? .primary : .secondary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background {
                                Capsule()
                                    .fill(isOn ? Color.primary.opacity(0.09) : Color(.secondarySystemBackground))
                                    .overlay(Capsule().stroke(Color.black.opacity(isOn ? 0.12 : 0.05), lineWidth: 0.7))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private var transparencyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
            Text("This may affect recommendations, suggested creators, and ranking. You can reset it anytime in Feed Intelligence settings.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onApply(draft)
                dismiss()
            } label: {
                Label("Apply to my feed", systemImage: "checkmark")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)
            .disabled(draft.affectedSurfaces.isEmpty)

            Button { onCancel(); dismiss() } label: {
                Text("Cancel")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func selectionPill(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.primary.opacity(0.09) : Color(.secondarySystemBackground))
                        .overlay(Capsule().stroke(Color.black.opacity(isSelected ? 0.12 : 0.05), lineWidth: 0.7))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
