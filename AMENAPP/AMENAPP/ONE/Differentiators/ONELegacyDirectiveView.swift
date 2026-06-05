// ONELegacyDirectiveView.swift
// ONE — Legacy directive: trustee assignment, bequest composer, memorialization.
// P4-H | one_activateLegacy CF is trustee-only; this view is owner-edit only.
//        Activation is blocked in this view — trustees activate via separate flow.

import SwiftUI

struct ONELegacyDirectiveView: View {
    @State private var directive: ONELegacyDirective
    var onSave: (ONELegacyDirective) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddTrustee = false
    @State private var showAddBequest = false
    @State private var showMemorialization = false

    init(directive: ONELegacyDirective? = nil, onSave: @escaping (ONELegacyDirective) -> Void) {
        let uid = "current_user"   // replaced at call site with Auth.auth().currentUser?.uid
        _directive = State(initialValue: directive ?? ONELegacyDirective(
            id: UUID().uuidString,
            ownerUID: uid,
            trustees: [],
            bequests: [],
            memorialization: .quietMemorial,
            activatedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                trusteesSection
                bequestsSection
                memorizationSection
                activationNotice
            }
            .navigationTitle("Legacy Directive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        directive.updatedAt = Date()
                        onSave(directive)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showAddTrustee) { addTrusteeSheet }
        .sheet(isPresented: $showAddBequest) { addBequestSheet }
    }

    // MARK: - Trustees section

    private var trusteesSection: some View {
        Section {
            ForEach(directive.trustees, id: \.uid) { trustee in
                trusteeRow(trustee)
            }
            .onDelete { idx in directive.trustees.remove(atOffsets: idx) }
            Button {
                showAddTrustee = true
            } label: {
                Label("Add Trustee", systemImage: "person.badge.plus")
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel("Add a trustee to your legacy directive")
        } header: {
            Text("Trustees")
        } footer: {
            Text("Trustees can activate your directive after your passing. They also receive vault items bequeathed to them.")
                .font(.caption)
        }
    }

    private func trusteeRow(_ trustee: ONETrustee) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trustee.displayName)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: ONE.Spacing.xs) {
                    if trustee.canActivate {
                        capabilityBadge("Can activate", color: ONE.Colors.witnessGold)
                    }
                    if trustee.canAccessVault {
                        capabilityBadge("Vault access", color: ONE.Colors.privateIndigo)
                    }
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trustee.displayName)\(trustee.canActivate ? ", can activate" : "")\(trustee.canAccessVault ? ", vault access" : "")")
    }

    private func capabilityBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    // MARK: - Bequests section

    private var bequestsSection: some View {
        Section {
            ForEach(directive.bequests) { bequest in
                bequestRow(bequest)
            }
            .onDelete { idx in directive.bequests.remove(atOffsets: idx) }
            Button {
                showAddBequest = true
            } label: {
                Label("Add Bequest", systemImage: "gift.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .disabled(directive.trustees.isEmpty)
            .accessibilityLabel("Add a vault item bequest")
            .accessibilityHint(directive.trustees.isEmpty ? "Add a trustee first" : "")
        } header: {
            Text("Bequests")
        } footer: {
            Text("Designate vault items to be delivered to trustees after activation.")
                .font(.caption)
        }
    }

    private func bequestRow(_ bequest: ONEMemoryBequest) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vault item → \(trusteeName(for: bequest.recipientUID))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(bequest.deliverAt, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let msg = bequest.message {
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func trusteeName(for uid: String) -> String {
        directive.trustees.first(where: { $0.uid == uid })?.displayName ?? uid
    }

    // MARK: - Memorialization section

    private var memorizationSection: some View {
        Section {
            ForEach([
                ONEMemorialization.archiveProfile,
                .quietMemorial,
                .memorialPage,
                .deleteAll
            ], id: \.rawValue) { option in
                memorizationRow(option)
            }
        } header: {
            Text("After Activation")
        } footer: {
            Text("What happens to your profile when your directive is activated.")
                .font(.caption)
        }
    }

    private func memorizationRow(_ option: ONEMemorialization) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                Text(option.memorialDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if directive.memorialization == option {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ONE.Colors.witnessGold)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { directive.memorialization = option }
        .accessibilityLabel("\(option.displayLabel): \(option.memorialDescription)\(directive.memorialization == option ? ", selected" : "")")
        .accessibilityAddTraits(directive.memorialization == option ? [.isSelected] : [])
    }

    // MARK: - Activation notice

    private var activationNotice: some View {
        Section {
            HStack(alignment: .top, spacing: ONE.Spacing.sm) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Text("Trustees activate this directive from their own devices. You cannot self-activate. The `one_activateLegacy` callable verifies trustee identity server-side.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Add trustee sheet

    private var addTrusteeSheet: some View {
        AddTrusteeSheet { trustee in
            directive.trustees.append(trustee)
        }
    }

    // MARK: - Add bequest sheet

    private var addBequestSheet: some View {
        AddBequestSheet(trustees: directive.trustees) { bequest in
            directive.bequests.append(bequest)
        }
    }
}

// MARK: - Add trustee sheet

private struct AddTrusteeSheet: View {
    var onAdd: (ONETrustee) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var uid = ""
    @State private var canActivate = true
    @State private var canAccessVault = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    TextField("Display name", text: $displayName)
                    TextField("UID or @handle", text: $uid)
                }
                Section("Permissions") {
                    Toggle("Can activate directive", isOn: $canActivate)
                        .tint(ONE.Colors.witnessGold)
                    Toggle("Vault access", isOn: $canAccessVault)
                        .tint(ONE.Colors.privateIndigo)
                }
            }
            .navigationTitle("Add Trustee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(ONETrustee(
                            uid: uid.trimmingCharacters(in: .whitespacesAndNewlines),
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            canActivate: canActivate,
                            canAccessVault: canAccessVault
                        ))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Add bequest sheet

private struct AddBequestSheet: View {
    let trustees: [ONETrustee]
    var onAdd: (ONEMemoryBequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrusteeUID = ""
    @State private var deliverAt = Date()
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    Picker("Trustee", selection: $selectedTrusteeUID) {
                        ForEach(trustees, id: \.uid) { t in
                            Text(t.displayName).tag(t.uid)
                        }
                    }
                }
                Section("Delivery") {
                    DatePicker("Deliver at", selection: $deliverAt, displayedComponents: .date)
                }
                Section("Message (optional)") {
                    TextEditor(text: $message)
                        .frame(minHeight: 60)
                }
            }
            .navigationTitle("Add Bequest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(ONEMemoryBequest(
                            id: UUID().uuidString,
                            vaultItemID: "",
                            recipientUID: selectedTrusteeUID,
                            deliverAt: deliverAt,
                            message: message.isEmpty ? nil : message
                        ))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedTrusteeUID.isEmpty)
                }
            }
            .onAppear {
                if selectedTrusteeUID.isEmpty {
                    selectedTrusteeUID = trustees.first?.uid ?? ""
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - ONEMemorialization UI metadata

extension ONEMemorialization {
    var displayLabel: String {
        switch self {
        case .archiveProfile: return "Archive"
        case .quietMemorial:  return "Quiet Memorial"
        case .memorialPage:   return "Memorial Page"
        case .deleteAll:      return "Delete Everything"
        }
    }

    var memorialDescription: String {
        switch self {
        case .archiveProfile: return "Profile frozen. No new interactions."
        case .quietMemorial:  return "Minimal presence. No engagement prompts."
        case .memorialPage:   return "Explicit memorial space with tributes."
        case .deleteAll:      return "All data deleted. Trustees verify before execution."
        }
    }
}
