import SwiftUI

struct AmenSmartComposerBar: View {
    @Binding var text: String
    let surface: AmenCommandLayerSurface
    let isSendEnabled: Bool
    let onCreateTapped: () -> Void
    let onModeTapped: () -> Void
    let onMicTapped: () -> Void
    let onSubmit: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            iconButton(systemImage: "plus", label: "Open create actions", action: onCreateTapped)

            TextField(surface.placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .font(.body)
                .textFieldStyle(.plain)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(submitIfValid)
                .accessibilityLabel(surface.placeholder)

            iconButton(systemImage: "slider.horizontal.3", label: "Open composer modes", action: onModeTapped)
            iconButton(systemImage: "mic", label: "Start voice input", action: onMicTapped)

            Button(action: submitIfValid) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(isSendEnabled ? Color.primary : Color.secondary.opacity(0.18), in: Circle())
                    .foregroundStyle(isSendEnabled ? Color(uiColor: .systemBackground) : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!isSendEnabled)
            .accessibilityLabel("Send")
            .accessibilityHint(isSendEnabled ? "Submits the composer text" : "Enter text or attach media before sending")
        }
        .padding(8)
        .background(commandSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.22 : 0.10), lineWidth: contrast == .increased ? 1.2 : 0.8)
        }
        .shadow(color: Color.black.opacity(reduceTransparency ? 0.06 : 0.12), radius: 18, y: 8)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.84), value: isSendEnabled)
        .accessibilityElement(children: .contain)
    }

    private var commandSurface: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemBackground)) : AnyShapeStyle(.regularMaterial)
    }

    private func iconButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(iconSurface, in: Circle())
                .foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var iconSurface: some ShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground)) : AnyShapeStyle(.thinMaterial)
    }

    private func submitIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSendEnabled, !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

struct AmenCreateActionSheet: View {
    let surface: AmenCommandLayerSurface
    let actions: [AmenCommandLayerAction]
    let onAction: (AmenCommandLayerAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(actions) { action in
                        AmenCommandActionRow(action: action) {
                            dismiss()
                            onAction(action)
                        }
                    }
                } footer: {
                    Text("Private until you post. Permissions are requested only after you choose an action that needs them.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(reduceTransparency ? Color(uiColor: .systemBackground) : Color.white.opacity(0.92))
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AmenAttachmentTray: View {
    let onAction: (AmenCommandLayerActionID) -> Void

    private let mediaActions: [AmenCommandLayerActionID] = [.camera, .photos, .addFiles]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.subheadline.weight(.semibold))
            ForEach(mediaActions) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(action.subtitle)
            }
            Label("Private until you post", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct AmenCommandActionRow: View {
    let action: AmenCommandLayerAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: action.id.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(action.id.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(action.unavailableReason ?? action.id.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: action.isAvailable ? "chevron.right" : "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(action.isAvailable ? .tertiary : .secondary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.id.title)
        .accessibilityHint(action.unavailableReason ?? action.id.subtitle)
    }
}

struct AmenContextualNavigationChips: View {
    let chips: [AmenContextualNavigationChip]
    let selectedID: String?
    let onSelect: (AmenContextualNavigationChip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onSelect(chip)
                    } label: {
                        Label(chip.title, systemImage: chip.systemImage)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(selectedID == chip.id ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.title)
                    .accessibilityAddTraits(selectedID == chip.id ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct AmenComposerModePicker: View {
    let surface: AmenCommandLayerSurface
    let onSelectAction: (AmenCommandLayerAction) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Relevant Actions") {
                    ForEach(AmenCommandLayerCatalog.actions(for: surface).prefix(8)) { action in
                        AmenCommandActionRow(action: action) {
                            onSelectAction(action)
                        }
                    }
                }
            }
            .navigationTitle("Composer Modes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
