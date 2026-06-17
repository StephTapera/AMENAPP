import SwiftUI

// MARK: - CCR-002 Light Glass Surface

/// Shared light-first Liquid Glass surface for CCR-002 menus, sheets, and pickers.
/// The fallback path is a solid warm surface for Reduce Transparency, not a weaker blur.
struct LightGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.basWarmPaper, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: Color.basInk.opacity(0.10), radius: 18, x: 0, y: 8)
        } else {
            content
                .background(Color.basWarmPaper.opacity(0.72), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.78), lineWidth: 1))
                .shadow(color: Color.basInk.opacity(0.14), radius: 22, x: 0, y: 10)
                .amenGlassEffect(in: shape)
        }
    }
}

extension View {
    func lightLiquidGlassSurface<S: InsettableShape>(in shape: S) -> some View {
        modifier(LightGlassSurfaceModifier(shape: shape))
    }
}

// MARK: - LiquidGlassMenu

struct LiquidGlassMenuItem: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let detail: String?
    let showsChevron: Bool
    let isDestructive: Bool

    init(
        id: String,
        icon: String,
        title: String,
        detail: String? = nil,
        showsChevron: Bool = false,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.detail = detail
        self.showsChevron = showsChevron
        self.isDestructive = isDestructive
    }
}

struct LiquidGlassMenuSection: Identifiable, Hashable {
    let id: String
    let title: String?
    let items: [LiquidGlassMenuItem]

    init(id: String, title: String? = nil, items: [LiquidGlassMenuItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// Floating light-first glass menu for attach menus and overflow menus.
struct LiquidGlassMenu: View {
    let title: String?
    let sections: [LiquidGlassMenuSection]
    let maxHeight: CGFloat
    let accessibilityLabel: String
    let onSelect: (LiquidGlassMenuItem) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String? = nil,
        sections: [LiquidGlassMenuSection],
        maxHeight: CGFloat = 360,
        accessibilityLabel: String = "Menu",
        onSelect: @escaping (LiquidGlassMenuItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.sections = sections
        self.maxHeight = maxHeight
        self.accessibilityLabel = accessibilityLabel
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.basInk.opacity(0.72))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.basInk.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss \(title)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        if let title = section.title {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.basInk.opacity(0.52))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                        }

                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            menuRow(item)
                            if index < section.items.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                                    .opacity(0.35)
                            }
                        }
                    }
                }
                .padding(.vertical, title == nil ? 8 : 0)
            }
            .frame(maxHeight: maxHeight)
        }
        .lightLiquidGlassSurface(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func menuRow(_ item: LiquidGlassMenuItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.isDestructive ? Color.red : Color.basInk)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(item.isDestructive ? Color.red : Color.basInk)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if let detail = item.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Color.basInk.opacity(0.50))
                        .lineLimit(1)
                }

                if item.showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.basInk.opacity(0.35))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.detail.map { "\(item.title), \($0)" } ?? item.title)
    }
}

// MARK: - LiquidGlassListPicker

struct LiquidGlassListPickerItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String

    init(id: String, title: String, subtitle: String, icon: String = "person.crop.circle") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }
}

/// Multi-select list picker with selected chips, cap enforcement, and confirm action.
struct LiquidGlassListPicker: View {
    let title: String
    let items: [LiquidGlassListPickerItem]
    @Binding var selection: Set<String>
    let selectionCap: Int?
    let capFootnote: String?
    let confirmTitle: String
    let onConfirm: (Set<String>) -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        title: String,
        items: [LiquidGlassListPickerItem],
        selection: Binding<Set<String>>,
        selectionCap: Int? = nil,
        capFootnote: String? = nil,
        confirmTitle: String = "Next",
        onConfirm: @escaping (Set<String>) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.items = items
        self._selection = selection
        self.selectionCap = selectionCap
        self.capFootnote = capFootnote
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            selectedChipRow
            listRows
        }
        .lightLiquidGlassSurface(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.basInk.opacity(0.46))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(title)")

            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.basInk)

            Spacer()

            Button(confirmTitle) {
                onConfirm(selection)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selection.isEmpty ? Color.basInk.opacity(0.38) : Color.basWineRed)
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var selectedChipRow: some View {
        if !selection.isEmpty || capFootnote != nil {
            VStack(alignment: .leading, spacing: 8) {
                if !selection.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedItems) { item in
                                selectedChip(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                if let capFootnote {
                    Text(capFootnote)
                        .font(.caption)
                        .foregroundStyle(Color.basInk.opacity(0.58))
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 10)
            Divider().opacity(0.25)
        }
    }

    private var listRows: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    pickerRow(item)
                    if item.id != items.last?.id {
                        Divider()
                            .padding(.leading, 64)
                            .opacity(0.32)
                    }
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private var selectedItems: [LiquidGlassListPickerItem] {
        items.filter { selection.contains($0.id) }
    }

    private func selectedChip(_ item: LiquidGlassListPickerItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.caption.weight(.semibold))
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(Color.basInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.basTan.opacity(0.86), in: Capsule())
        .onTapGesture { selection.remove(item.id) }
        .accessibilityLabel("Remove \(item.title)")
        .accessibilityAddTraits(.isButton)
    }

    private func pickerRow(_ item: LiquidGlassListPickerItem) -> some View {
        let isSelected = selection.contains(item.id)
        let isAtCap = selectionCap.map { selection.count >= $0 } ?? false
        let isDisabled = !isSelected && isAtCap

        return Button {
            toggle(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(isDisabled ? Color.basInk.opacity(0.28) : Color.basInk)
                    .frame(width: 36, height: 36)
                    .background(Color.basTan.opacity(isDisabled ? 0.38 : 0.8), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isDisabled ? Color.basInk.opacity(0.36) : Color.basInk)
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.basInk.opacity(isDisabled ? 0.32 : 0.56))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.basWineRed : Color.basInk.opacity(0.32))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("\(item.title), \(item.subtitle)\(isSelected ? ", selected" : "")")
        .accessibilityHint(isDisabled ? "Selection limit reached" : "Toggle selection")
    }

    private func toggle(_ item: LiquidGlassListPickerItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
            return
        }

        if let selectionCap, selection.count >= selectionCap {
            return
        }

        selection.insert(item.id)
    }
}

// MARK: - BereanComposerMenu

enum BereanComposerMenuAction: String, CaseIterable, Identifiable {
    case addScripture
    case attachNote
    case scanText
    case photo
    case capabilities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addScripture: return "Add Scripture"
        case .attachNote: return "Attach Note"
        case .scanText: return "Scan Text"
        case .photo: return "Photo"
        case .capabilities: return "@ Capabilities"
        }
    }

    var icon: String {
        switch self {
        case .addScripture: return "book.fill"
        case .attachNote: return "note.text"
        case .scanText: return "text.viewfinder"
        case .photo: return "photo.on.rectangle"
        case .capabilities: return "at"
        }
    }

    var detail: String? {
        switch self {
        case .scanText: return "On-device OCR"
        case .photo: return "Guarded"
        case .capabilities: return "Plugins"
        default: return nil
        }
    }

    var menuItem: LiquidGlassMenuItem {
        LiquidGlassMenuItem(id: id, icon: icon, title: title, detail: detail, showsChevron: self == .capabilities)
    }
}

struct BereanComposerMenu: View {
    let onSelect: (BereanComposerMenuAction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        LiquidGlassMenu(
            title: "Add to Berean",
            sections: [
                LiquidGlassMenuSection(
                    id: "compose",
                    items: [
                        BereanComposerMenuAction.addScripture.menuItem,
                        BereanComposerMenuAction.attachNote.menuItem,
                        BereanComposerMenuAction.scanText.menuItem,
                        BereanComposerMenuAction.photo.menuItem,
                        BereanComposerMenuAction.capabilities.menuItem
                    ]
                )
            ],
            accessibilityLabel: "Berean composer menu",
            onSelect: { item in
                guard let action = BereanComposerMenuAction(rawValue: item.id) else { return }
                onSelect(action)
            },
            onDismiss: onDismiss
        )
    }
}

// MARK: - BereanAgentActivitySheet

struct BereanAgentActivityStep: Identifiable, Hashable {
    enum State: Hashable {
        case pending
        case running
        case complete
    }

    let id: String
    let title: String
    let state: State

    init(id: String, title: String, state: State) {
        self.id = id
        self.title = title
        self.state = state
    }
}

struct BereanAgentActivitySheet: View {
    let modeName: String
    let currentTask: String
    let steps: [BereanAgentActivityStep]
    let provenanceSources: [String]
    let references: [String]
    let onDismiss: () -> Void

    init(
        modeName: String,
        currentTask: String,
        steps: [BereanAgentActivityStep],
        provenanceSources: [String],
        references: [String] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.modeName = modeName
        self.currentTask = currentTask
        self.steps = steps
        self.provenanceSources = provenanceSources
        self.references = references
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(modeName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Color.basInk)
                    Text(currentTask.isEmpty ? "Working" : currentTask)
                        .font(.subheadline)
                        .foregroundStyle(Color.basInk.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.basInk.opacity(0.46))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss activity")
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(steps) { step in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: step.state))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(color(for: step.state))
                            .frame(width: 22)
                            .accessibilityHidden(true)

                        Text(step.title)
                            .font(.subheadline.weight(step.state == .running ? .semibold : .regular))
                            .foregroundStyle(Color.basInk.opacity(step.state == .pending ? 0.48 : 0.86))
                    }
                    .accessibilityLabel("\(step.title), \(label(for: step.state))")
                }
            }

            provenanceLine

            if !references.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("References")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.basInk.opacity(0.58))
                    ForEach(references, id: \.self) { reference in
                        Text(reference)
                            .font(.caption)
                            .foregroundStyle(Color.basInk.opacity(0.70))
                    }
                }
            }
        }
        .padding(20)
        .lightLiquidGlassSurface(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Berean activity")
    }

    private var provenanceLine: some View {
        let sources = provenanceSources.isEmpty ? "No external sources" : provenanceSources.joined(separator: " - ")

        return Text("Berean is using: \(sources)")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.basInk.opacity(0.68))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.basTan.opacity(0.62), in: Capsule())
            .accessibilityLabel("Berean is using \(sources)")
    }

    private func icon(for state: BereanAgentActivityStep.State) -> String {
        switch state {
        case .pending: return "circle"
        case .running: return "arrow.triangle.2.circlepath"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private func color(for state: BereanAgentActivityStep.State) -> Color {
        switch state {
        case .pending: return Color.basInk.opacity(0.34)
        case .running: return Color.basWineRed
        case .complete: return Color(.systemGreen)
        }
    }

    private func label(for state: BereanAgentActivityStep.State) -> String {
        switch state {
        case .pending: return "pending"
        case .running: return "running"
        case .complete: return "complete"
        }
    }
}

#if DEBUG
#Preview("CCR-002 Menu") {
    VStack {
        Spacer()
        BereanComposerMenu(onSelect: { _ in }, onDismiss: {})
            .padding()
    }
    .background(Color.basWarmPaper)
}

#Preview("CCR-002 List Picker") {
    @Previewable @State var selected: Set<String> = ["miriam"]
    LiquidGlassListPicker(
        title: "Add People",
        items: [
            LiquidGlassListPickerItem(id: "miriam", title: "Miriam Stone", subtitle: "Worship team"),
            LiquidGlassListPickerItem(id: "jonah", title: "Jonah Reed", subtitle: "Small group"),
            LiquidGlassListPickerItem(id: "lydia", title: "Lydia Chen", subtitle: "Prayer team")
        ],
        selection: $selected,
        selectionCap: 3,
        capFootnote: "Up to 3 including you",
        onConfirm: { _ in },
        onDismiss: {}
    )
    .padding()
    .background(Color.basWarmPaper)
}

#Preview("CCR-002 Activity Sheet") {
    BereanAgentActivitySheet(
        modeName: "Agent Mode",
        currentTask: "Checking cross-references for Romans 8",
        steps: [
            BereanAgentActivityStep(id: "scripture", title: "Searching Scripture", state: .complete),
            BereanAgentActivityStep(id: "cross", title: "Checking cross-references", state: .running),
            BereanAgentActivityStep(id: "reflect", title: "Reflecting", state: .pending)
        ],
        provenanceSources: ["Scripture", "your notes"],
        references: ["Romans 8:1", "John 15:5"],
        onDismiss: {}
    )
    .padding()
    .background(Color.basWarmPaper)
}
#endif
