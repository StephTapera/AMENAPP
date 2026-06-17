import SwiftUI

enum SettingsDesignToken {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
    }

    enum CornerRadius {
        static let row: CGFloat = 8
        static let card: CGFloat = 8
        static let modal: CGFloat = 20
    }

    enum Typography {
        static let sectionTitle: Font = .headline
        static let rowTitle: Font = .body
        static let caption: Font = .footnote
    }
}

struct SettingsRootView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.large) {
                    content
                }
                .padding(SettingsDesignToken.Spacing.large)
            }
            .navigationTitle("Settings")
        }
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String?
    let footer: String?
    private let content: Content

    init(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.small) {
            if let title {
                Text(title)
                    .font(SettingsDesignToken.Typography.sectionTitle)
            }

            VStack(spacing: 0) {
                content
            }
            .padding(SettingsDesignToken.Spacing.medium)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: SettingsDesignToken.CornerRadius.card, style: .continuous))

            if let footer {
                Text(footer)
                    .font(SettingsDesignToken.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let icon: String?
    let title: String
    let value: String?
    let chevron: Bool
    private let accessory: Accessory
    private let action: (() -> Void)?

    init(
        icon: String? = nil,
        title: String,
        value: String? = nil,
        chevron: Bool = false,
        @ViewBuilder accessory: () -> Accessory,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.chevron = chevron
        self.accessory = accessory()
        self.action = action
    }

    var body: some View {
        Button(action: { action?() }) {
            HStack(spacing: SettingsDesignToken.Spacing.medium) {
                if let icon {
                    Image(systemName: icon)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(SettingsDesignToken.Typography.rowTitle)
                    .foregroundStyle(.primary)

                Spacer(minLength: SettingsDesignToken.Spacing.medium)

                if let value {
                    Text(value)
                        .font(SettingsDesignToken.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                accessory

                if chevron {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, SettingsDesignToken.Spacing.small)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(
        icon: String? = nil,
        title: String,
        value: String? = nil,
        chevron: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(icon: icon, title: title, value: value, chevron: chevron, accessory: { EmptyView() }, action: action)
    }
}

struct LiquidGlassModal<Content: View>: View {
    let title: String
    let onClose: () -> Void
    private let content: Content

    init(
        title: String,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .padding(SettingsDesignToken.Spacing.large)
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

struct ToggleSettingRow: View {
    let title: String
    let caption: String?
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void

    init(
        title: String,
        caption: String? = nil,
        binding: Binding<Bool>,
        onChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.caption = caption
        self._isOn = binding
        self.onChange = onChange
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: SettingsDesignToken.Spacing.xSmall) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(SettingsDesignToken.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: isOn) { _, newValue in onChange(newValue) }
    }
}

struct PickerSettingRow<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [Selection]

    init(title: String, selection: Binding<Selection>, options: [Selection]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(String(describing: option)).tag(option)
            }
        }
    }
}

struct StorageUsageView: View {
    let breakdown: StorageBreakdown

    var body: some View {
        VStack(alignment: .leading) {
            Text(ByteCountFormatter.string(fromByteCount: breakdown.total, countStyle: .file))
                .font(.headline)
            ProgressView(value: breakdown.total == 0 ? 0.0 : 1.0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Storage used")
    }
}

struct SecuritySessionsView: View {
    let sessions: [SessionInfo]
    let revoke: (SessionInfo) -> Void

    var body: some View {
        VStack(spacing: SettingsDesignToken.Spacing.small) {
            ForEach(sessions) { session in
                SettingsRow(
                    icon: session.isCurrent ? "iphone" : "desktopcomputer",
                    title: session.deviceName,
                    value: session.platform,
                    chevron: false,
                    action: { revoke(session) }
                )
            }
        }
    }
}

struct ReportIssueSheet: View {
    @Binding var report: IssueReport
    let submit: (IssueReport) -> Void

    var body: some View {
        Form {
            Picker("Category", selection: $report.category) {
                ForEach(IssueReportCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }

            TextEditor(text: $report.body)
                .frame(minHeight: 160)

            Text("\(report.body.count)/\(IssueReport.maxBodyCharacterCount)")
                .foregroundStyle(report.body.count > IssueReport.maxBodyCharacterCount ? .red : .secondary)

            Toggle("Include screenshot", isOn: $report.includeScreenshot)
            Toggle("Include logs", isOn: $report.includeLogs)
            Button("Submit") { submit(report) }
                .disabled(report.body.isEmpty || report.body.count > IssueReport.maxBodyCharacterCount)
        }
    }
}

struct TrustedContactView: View {
    let contacts: [SettingsTrustedContact]
    let addContact: () -> Void
    let removeContact: (SettingsTrustedContact) -> Void

    var body: some View {
        VStack {
            ForEach(contacts) { contact in
                SettingsRow(
                    title: contact.displayName,
                    value: contact.contactMethod.maskedValue,
                    action: { removeContact(contact) }
                )
            }
            Button("Add trusted contact", action: addContact)
        }
    }
}

struct ParentalControlsView: View {
    @Binding var controls: ParentalControls

    var body: some View {
        SettingsSectionCard(title: "Parental Controls") {
            Text("Guardian views are limited to safety flags and account controls.")
                .font(SettingsDesignToken.Typography.caption)
                .foregroundStyle(.secondary)
            ToggleSettingRow(title: "Screen time reminders", binding: $controls.screenTimeReminders)
        }
    }
}

struct NotificationPreferencesView: View {
    @Binding var preferences: NotificationPrefs

    var body: some View {
        SettingsSectionCard(title: "Notifications") {
            ForEach(SettingsNotificationCategory.allCases) { category in
                Picker(category.rawValue, selection: Binding(
                    get: { preferences.categories[category] ?? category.minimumAllowedChoice ?? .quiet },
                    set: { preferences.categories[category] = $0 }
                )) {
                    ForEach(ChannelChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
            }
        }
    }
}

struct DataControlsView: View {
    let requestExport: () -> Void
    let requestAccountDeletion: () -> Void
    let deleteAiMemory: () -> Void

    var body: some View {
        SettingsSectionCard(title: "Data Controls") {
            Button("Download my data", action: requestExport)
            Button("Delete AI memory", role: .destructive, action: deleteAiMemory)
            Button("Delete account", role: .destructive, action: requestAccountDeletion)
        }
    }
}
