// CrisisSafetyPlanModule.swift
// AMENAPP
//
// Safety Plan + Trusted Contacts for the Crisis Support system.
// Privacy-first: stored locally by default. No social visibility.
// User controls exactly what is shared and with whom.
//

import SwiftUI

// MARK: - Safety Plan Module

struct CrisisSafetyPlanModule: View {
    @Bindable var viewModel: CrisisSupportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.safetyPlan.isEmpty {
                emptyPlanState
            } else {
                activePlanView
            }
        }
    }

    // MARK: - Empty State (no plan saved yet)

    private var emptyPlanState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You don't have a Safety Plan yet.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button {
                viewModel.isSafetyPlanSetupOpen = true
            } label: {
                Label("Create My Safety Plan", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 0.13, green: 0.60, blue: 0.29))
                    )
            }
            .buttonStyle(.plain)

            Text("Built with Berean guidance. Stored privately on your device.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .sheet(isPresented: $viewModel.isSafetyPlanSetupOpen) {
            SafetyPlanSetupSheet(viewModel: viewModel)
        }
    }

    // MARK: - Active Plan View

    private var activePlanView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Activate button
            Button {
                viewModel.activateSafetyPlan()
            } label: {
                HStack {
                    Image(systemName: viewModel.isSafetyPlanActivated ? "checkmark.shield.fill" : "shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(viewModel.isSafetyPlanActivated ? "Plan Active" : "Activate My Safety Plan")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.vertical, 13)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(viewModel.isSafetyPlanActivated
                              ? Color(red: 0.13, green: 0.60, blue: 0.29)
                              : Color(red: 0.10, green: 0.45, blue: 0.22))
                )
            }
            .buttonStyle(.plain)
            .animation(CrisisAnimationTokens.sectionExpand, value: viewModel.isSafetyPlanActivated)

            // Plan sections (visible when activated or always)
            planRows
        }
        .sheet(isPresented: $viewModel.isSafetyPlanSetupOpen) {
            SafetyPlanSetupSheet(viewModel: viewModel)
        }
    }

    private var planRows: some View {
        VStack(spacing: 8) {
            if !viewModel.safetyPlan.warningSigns.isEmpty {
                SafetyPlanRow(icon: "exclamationmark.triangle", title: "Warning Signs", items: viewModel.safetyPlan.warningSigns)
            }
            if !viewModel.safetyPlan.groundingStrategies.isEmpty {
                SafetyPlanRow(icon: "circle.dotted", title: "Things That Help", items: viewModel.safetyPlan.groundingStrategies)
            }
            if !viewModel.safetyPlan.trustedPeople.isEmpty {
                SafetyPlanRow(icon: "person.2.fill", title: "People I Can Call", items: viewModel.safetyPlan.trustedPeople)
            }
            if !viewModel.safetyPlan.professionalResources.isEmpty {
                SafetyPlanRow(icon: "stethoscope", title: "Professional Support", items: viewModel.safetyPlan.professionalResources)
            }
            if !viewModel.safetyPlan.faithReminders.isEmpty {
                SafetyPlanRow(icon: "hands.sparkles", title: "Faith Reminders", items: viewModel.safetyPlan.faithReminders)
            }

            // Edit button
            Button {
                viewModel.isSafetyPlanSetupOpen = true
            } label: {
                Label("Edit Plan", systemImage: "pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Safety Plan Row

private struct SafetyPlanRow: View {
    let icon: String
    let title: String
    let items: [String]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(CrisisAnimationTokens.sectionExpand) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(items[i])
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Safety Plan Setup Sheet

struct SafetyPlanSetupSheet: View {
    @Bindable var viewModel: CrisisSupportViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var warningSigns: String = ""
    @State private var groundingStrategies: String = ""
    @State private var trustedPeople: String = ""
    @State private var professionalResources: String = ""
    @State private var safePlaces: String = ""
    @State private var faithReminders: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    planFieldEditor("Warning signs I notice", text: $warningSigns)
                } header: {
                    Label("Warning Signs", systemImage: "exclamationmark.triangle")
                } footer: {
                    Text("What do you notice when things are getting harder?")
                }

                Section {
                    planFieldEditor("Things that help me stay calm", text: $groundingStrategies)
                } header: {
                    Label("Things That Help", systemImage: "circle.dotted")
                } footer: {
                    Text("Activities, environments, or sensory tools that ground you.")
                }

                Section {
                    planFieldEditor("Names and numbers", text: $trustedPeople)
                } header: {
                    Label("People I Can Call", systemImage: "person.2")
                } footer: {
                    Text("People who are safe to reach in a difficult moment.")
                }

                Section {
                    planFieldEditor("Therapist, counselor, or crisis line", text: $professionalResources)
                } header: {
                    Label("Professional Support", systemImage: "stethoscope")
                }

                Section {
                    planFieldEditor("Quiet places, familiar spaces", text: $safePlaces)
                } header: {
                    Label("Safe Places", systemImage: "house.fill")
                }

                Section {
                    planFieldEditor("Verses, prayers, or words that anchor me", text: $faithReminders)
                } header: {
                    Label("Faith Reminders (optional)", systemImage: "hands.sparkles")
                } footer: {
                    Text("Only what you want. Leave blank to skip.")
                }

                Section {
                    Text("Your Safety Plan is stored privately on your device. It is not shared with anyone, visible to followers, or accessible to any social surface in AMEN.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("My Safety Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear { loadExisting() }
    }

    @ViewBuilder
    private func planFieldEditor(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .lineLimit(2...5)
            .font(.system(size: 15))
    }

    private func split(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() {
        viewModel.safetyPlan.warningSigns          = split(warningSigns)
        viewModel.safetyPlan.groundingStrategies   = split(groundingStrategies)
        viewModel.safetyPlan.trustedPeople         = split(trustedPeople)
        viewModel.safetyPlan.professionalResources = split(professionalResources)
        viewModel.safetyPlan.safePlaces            = split(safePlaces)
        viewModel.safetyPlan.faithReminders        = split(faithReminders)
        viewModel.saveSafetyPlan()
        dismiss()
    }

    private func loadExisting() {
        let p = viewModel.safetyPlan
        warningSigns          = p.warningSigns.joined(separator: "\n")
        groundingStrategies   = p.groundingStrategies.joined(separator: "\n")
        trustedPeople         = p.trustedPeople.joined(separator: "\n")
        professionalResources = p.professionalResources.joined(separator: "\n")
        safePlaces            = p.safePlaces.joined(separator: "\n")
        faithReminders        = p.faithReminders.joined(separator: "\n")
    }
}

// MARK: - Trusted Contact Module

struct CrisisTrustedContactModule: View {
    @Bindable var viewModel: CrisisSupportViewModel
    @State private var showAddContact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.trustedContacts.isEmpty {
                emptyContactState
            } else {
                contactList
            }
        }
        .sheet(isPresented: $showAddContact) {
            CrisisAddTrustedContactSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showTrustedContactSheet) {
            TrustedContactMessageSheet(viewModel: viewModel)
        }
    }

    private var emptyContactState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add one safe person you can reach right now.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Button {
                showAddContact = true
            } label: {
                Label("Add a Trusted Person", systemImage: "person.badge.plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.70, green: 0.42, blue: 0.05))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 1.00, green: 0.96, blue: 0.90))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color(red: 0.70, green: 0.42, blue: 0.05).opacity(0.14), lineWidth: 0.6)
                            )
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var contactList: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.trustedContacts) { contact in
                CrisisTrustedContactRow(contact: contact) {
                    viewModel.prepareTrustedContactMessage(contact: contact)
                }
            }

            Button {
                showAddContact = true
            } label: {
                Label("Add Another", systemImage: "plus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// MARK: - Trusted Contact Row

private struct CrisisTrustedContactRow: View {
    let contact: CrisisTrustedContact
    let onReach: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Initials avatar
            Text(contact.name.prefix(1).uppercased())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(red: 0.70, green: 0.42, blue: 0.05).opacity(0.80)))

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 15, weight: .medium))
                Text(contact.relationship + (contact.isPastor ? " · Pastor" : ""))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onReach) {
                Text("Reach")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.70, green: 0.42, blue: 0.05))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(red: 1.00, green: 0.96, blue: 0.90))
                            .overlay(Capsule().stroke(Color(red: 0.70, green: 0.42, blue: 0.05).opacity(0.14), lineWidth: 0.6))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Add Trusted Contact Sheet

private struct CrisisAddTrustedContactSheet: View {
    @Bindable var viewModel: CrisisSupportViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var relationship: String = ""
    @State private var isPastor: Bool = false
    @State private var shareTemplate: String = "Hey — I could use some support right now. Can we talk?"

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Name", text: $name)
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("Relationship (e.g. friend, spouse)", text: $relationship)
                }
                Section {
                    Toggle("This person is my pastor", isOn: $isPastor)
                } footer: {
                    Text("Pastor contacts will only be reached when you explicitly choose to.")
                }
                Section("Default Message") {
                    TextField("Message to send when you reach out", text: $shareTemplate, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text("This contact is stored privately on your device. Nothing is sent automatically. You control every outreach.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Trusted Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let contact = CrisisTrustedContact(
                            name: name, phoneNumber: phone,
                            relationship: relationship, isPastor: isPastor,
                            shareTemplate: shareTemplate
                        )
                        viewModel.addTrustedContact(contact)
                        dismiss()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Trusted Contact Message Sheet

struct TrustedContactMessageSheet: View {
    @Bindable var viewModel: CrisisSupportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let contact = viewModel.selectedTrustedContact {
                    // Contact info
                    HStack(spacing: 12) {
                        Text(contact.name.prefix(1).uppercased())
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color(red: 0.70, green: 0.42, blue: 0.05).opacity(0.80)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(contact.name)
                                .font(.system(size: 17, weight: .semibold))
                            Text(contact.relationship)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Editable message
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your message (you can edit before sending)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        TextEditor(text: $viewModel.pendingContactMessage)
                            .font(.system(size: 15))
                            .frame(minHeight: 100)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            )
                    }

                    Text("Only you can send this message. Nothing is sent automatically. Your pastor or contact will only hear from you if you choose.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)

                    Spacer()

                    // Send button
                    Button {
                        viewModel.sendTrustedContactMessage()
                        dismiss()
                    } label: {
                        Text("Send Message via SMS")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(red: 0.70, green: 0.42, blue: 0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .navigationTitle("Reach Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
