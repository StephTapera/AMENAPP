//
//  ChurchEditProfileView.swift
//  AMENAPP
//
//  Role-aware edit profile sheet for Church and Business accounts.
//  Shows contextually different field sections based on AMENAccountType.
//
//  Design system:
//  - White background, black text
//  - Liquid Glass: .ultraThinMaterial + Color.white.opacity(0.55) overlay
//                  + Color(white: 0.88).opacity(0.5) strokeBorder 0.5pt
//                  + shadow black 0.06 radius 12
//  - Typography: AMENFont
//
//  Pure SwiftUI + Foundation — NO Firebase imports.
//

import SwiftUI
import Foundation

// MARK: - ChurchEditProfileView

struct ChurchEditProfileView: View {

    // MARK: Parameters

    let accountType: AMENAccountType

    // MARK: Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: Shared editable state

    @State private var username: String = ""
    @State private var coverPhotoPlaceholder: Bool = false  // placeholder for cover photo upload

    // MARK: Church-specific state

    @State private var churchDisplayName: String = ""
    @State private var churchBio: String = ""
    @State private var churchWebsiteURL: String = ""
    @State private var churchLivestreamURL: String = ""
    @State private var churchGivingURL: String = ""
    @State private var churchPhone: String = ""
    @State private var churchEmail: String = ""
    @State private var churchDenomination: String = ""
    @State private var churchVerificationStatus: VerificationStatus = .unverified

    // Address fields
    @State private var addressStreet: String = ""
    @State private var addressCity: String = ""
    @State private var addressState: String = ""
    @State private var addressZip: String = ""

    // Service times
    @State private var serviceTimes: [ChurchServiceTime] = []
    @State private var newServiceDay: String = ""
    @State private var newServiceTime: String = ""
    @State private var newServiceLabel: String = ""
    @State private var isAddingServiceTime: Bool = false

    // MARK: Business-specific state

    @State private var businessDisplayName: String = ""
    @State private var businessBio: String = ""
    @State private var businessWebsiteURL: String = ""
    @State private var businessContactEmail: String = ""
    @State private var businessCategory: String = ""
    @State private var businessMissionStatement: String = ""
    @State private var businessLinks: [String] = []
    @State private var newBusinessLink: String = ""
    @State private var analyticsEnabled: Bool = false

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // ── Shared: Cover Photo Upload ──────────────────────────
                    sectionCard(header: "Cover Photo") {
                        uploadPlaceholder(
                            icon: "photo.on.rectangle.angled",
                            label: "Upload Cover Photo",
                            subtitle: "Recommended: 1500 × 500"
                        )
                    }

                    // ── Shared: Logo Upload ─────────────────────────────────
                    sectionCard(header: "Logo") {
                        uploadPlaceholder(
                            icon: "photo.circle",
                            label: "Upload Logo",
                            subtitle: "Recommended: 400 × 400"
                        )
                    }

                    // ── Shared: Username ────────────────────────────────────
                    sectionCard(header: "Username") {
                        labeledTextField("@username", text: $username)
                    }

                    // ── Type-specific sections ──────────────────────────────
                    switch accountType {
                    case .church:
                        churchSections
                    case .business:
                        businessSections
                    case .personal:
                        EmptyView()
                    }

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(AMENFont.regular(15))
                        .foregroundColor(.black.opacity(0.7))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { handleSave() }
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.black)
                }
            }
        }
    }

    // MARK: - Church Sections

    @ViewBuilder
    private var churchSections: some View {

        // Display Name
        sectionCard(header: "Display Name") {
            labeledTextField("Church name", text: $churchDisplayName)
        }

        // Bio
        sectionCard(header: "Bio") {
            bioEditor($churchBio, placeholder: "Describe your church community...")
        }

        // Online Presence
        sectionCard(header: "Online Presence") {
            VStack(spacing: 0) {
                labeledTextField("Website URL", text: $churchWebsiteURL)
                fieldDivider
                labeledTextField("Livestream URL", text: $churchLivestreamURL)
                fieldDivider
                labeledTextField("Giving URL", text: $churchGivingURL)
            }
        }

        // Contact
        sectionCard(header: "Contact") {
            VStack(spacing: 0) {
                labeledTextField("Phone", text: $churchPhone)
                    .keyboardType(.phonePad)
                fieldDivider
                labeledTextField("Email", text: $churchEmail)
                    .keyboardType(.emailAddress)
            }
        }

        // Address
        sectionCard(header: "Address") {
            VStack(spacing: 0) {
                labeledTextField("Street", text: $addressStreet)
                fieldDivider
                labeledTextField("City", text: $addressCity)
                fieldDivider
                labeledTextField("State", text: $addressState)
                fieldDivider
                labeledTextField("ZIP Code", text: $addressZip)
                    .keyboardType(.numbersAndPunctuation)
            }
        }

        // Denomination
        sectionCard(header: "Denomination") {
            labeledTextField("e.g. Baptist, Methodist, Non-denominational", text: $churchDenomination)
        }

        // Service Times
        sectionCard(header: "Service Times") {
            VStack(spacing: 0) {
                if serviceTimes.isEmpty {
                    Text("No service times added yet.")
                        .font(AMENFont.regular(14))
                        .foregroundColor(.black.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(serviceTimes.enumerated()), id: \.element.id) { index, time in
                        serviceTimeRow(time: time, index: index)
                        if index < serviceTimes.count - 1 {
                            fieldDivider
                        }
                    }
                }

                if isAddingServiceTime {
                    fieldDivider
                    addServiceTimeForm
                }

                Divider().padding(.vertical, 4)

                Button {
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82))) {
                        isAddingServiceTime = true
                    }
                } label: {
                    Label("Add Service Time", systemImage: "plus.circle")
                        .font(AMENFont.semiBold(14))
                        .foregroundColor(.black)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
        }

        // Verification status (read-only)
        sectionCard(header: "Verification Status") {
            HStack(spacing: 10) {
                verificationStatusBadge(churchVerificationStatus)
                Text(verificationStatusDescription(churchVerificationStatus))
                    .font(AMENFont.regular(13))
                    .foregroundColor(.black.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Business Sections

    @ViewBuilder
    private var businessSections: some View {

        // Display Name
        sectionCard(header: "Display Name") {
            labeledTextField("Organization name", text: $businessDisplayName)
        }

        // Bio
        sectionCard(header: "Bio") {
            bioEditor($businessBio, placeholder: "Describe your organization...")
        }

        // Online Presence
        sectionCard(header: "Website") {
            labeledTextField("Website URL", text: $businessWebsiteURL)
        }

        // Contact
        sectionCard(header: "Contact Email") {
            labeledTextField("contact@example.com", text: $businessContactEmail)
                .keyboardType(.emailAddress)
        }

        // Category
        sectionCard(header: "Category") {
            labeledTextField("e.g. Ministry, Non-profit, Education", text: $businessCategory)
        }

        // Mission Statement
        sectionCard(header: "Mission Statement") {
            bioEditor($businessMissionStatement, placeholder: "Share your organization's mission...")
        }

        // Business Links
        sectionCard(header: "Business Links") {
            VStack(spacing: 0) {
                if businessLinks.isEmpty {
                    Text("No links added yet.")
                        .font(AMENFont.regular(14))
                        .foregroundColor(.black.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(businessLinks.enumerated()), id: \.offset) { index, link in
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.systemScaled(13))
                                .foregroundColor(.black.opacity(0.4))
                            Text(link)
                                .font(AMENFont.regular(15))
                                .foregroundColor(.black)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                businessLinks.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.systemScaled(18))
                                    .foregroundColor(.black.opacity(0.3))
                            }
                        }
                        .padding(.vertical, 10)
                        if index < businessLinks.count - 1 {
                            fieldDivider
                        }
                    }
                }

                Divider().padding(.vertical, 4)

                HStack(spacing: 8) {
                    TextField("Add a link...", text: $newBusinessLink)
                        .font(.systemScaled(15))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button {
                        let trimmed = newBusinessLink.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        businessLinks.append(trimmed)
                        newBusinessLink = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(20))
                            .foregroundColor(.black)
                    }
                }
                .padding(.vertical, 8)
            }
        }

        // Analytics
        sectionCard(header: "Analytics") {
            Toggle(isOn: $analyticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Analytics")
                        .font(AMENFont.semiBold(15))
                        .foregroundColor(.black)
                    Text("View insights about your audience and content performance.")
                        .font(AMENFont.regular(12))
                        .foregroundColor(.black.opacity(0.5))
                }
            }
            .tint(.black)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Reusable Subviews

    @ViewBuilder
    private func sectionCard<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header.uppercased())
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
    }

    private func labeledTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.systemScaled(15))
            .textFieldStyle(.plain)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func bioEditor(_ text: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.systemScaled(15))
                    .foregroundColor(.black.opacity(0.3))
                    .padding(.top, 8)
            }
            TextEditor(text: text)
                .font(.systemScaled(15))
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.top, 2)
        }
    }

    private var fieldDivider: some View {
        Divider()
            .background(Color(white: 0.88))
    }

    @ViewBuilder
    private func uploadPlaceholder(icon: String, label: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: 0.95))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.systemScaled(22))
                    .foregroundColor(.black.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(AMENFont.semiBold(15))
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(AMENFont.regular(12))
                    .foregroundColor(.black.opacity(0.4))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundColor(.black.opacity(0.25))
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func serviceTimeRow(time: ChurchServiceTime, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time.dayOfWeek)
                    .font(AMENFont.semiBold(14))
                    .foregroundColor(.black)
                HStack(spacing: 6) {
                    Text(time.startTime)
                        .font(AMENFont.regular(13))
                        .foregroundColor(.black.opacity(0.6))
                    if let label = time.label, !label.isEmpty {
                        Text("·")
                            .foregroundColor(.black.opacity(0.3))
                        Text(label)
                            .font(AMENFont.regular(13))
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
            }
            Spacer()
            Button {
                serviceTimes.remove(at: index)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.systemScaled(18))
                    .foregroundColor(.black.opacity(0.3))
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var addServiceTimeForm: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Day (e.g. Sunday)", text: $newServiceDay)
                    .font(.systemScaled(14))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 20)
                TextField("Time (e.g. 10:00 AM)", text: $newServiceTime)
                    .font(.systemScaled(14))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
            TextField("Label (e.g. Main Service)", text: $newServiceLabel)
                .font(.systemScaled(14))
                .textFieldStyle(.plain)
            HStack(spacing: 8) {
                Button("Cancel") {
                    newServiceDay = ""
                    newServiceTime = ""
                    newServiceLabel = ""
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82))) {
                        isAddingServiceTime = false
                    }
                }
                .font(AMENFont.regular(13))
                .foregroundColor(.black.opacity(0.5))
                Spacer()
                Button("Add") {
                    let trimDay  = newServiceDay.trimmingCharacters(in: .whitespaces)
                    let trimTime = newServiceTime.trimmingCharacters(in: .whitespaces)
                    guard !trimDay.isEmpty, !trimTime.isEmpty else { return }
                    let entry = ChurchServiceTime(
                        dayOfWeek: trimDay,
                        startTime: trimTime,
                        label: newServiceLabel.trimmingCharacters(in: .whitespaces).isEmpty ? nil : newServiceLabel.trimmingCharacters(in: .whitespaces)
                    )
                    serviceTimes.append(entry)
                    newServiceDay = ""
                    newServiceTime = ""
                    newServiceLabel = ""
                    withAnimation(Motion.adaptive(.spring(response: 0.35, dampingFraction: 0.82))) {
                        isAddingServiceTime = false
                    }
                }
                .font(AMENFont.semiBold(13))
                .foregroundColor(.black)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func verificationStatusBadge(_ status: VerificationStatus) -> some View {
        HStack(spacing: 5) {
            Image(systemName: verificationIcon(status))
                .font(.systemScaled(12, weight: .semibold))
                .foregroundColor(verificationColor(status))
            Text(verificationLabel(status))
                .font(AMENFont.semiBold(12))
                .foregroundColor(.black.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(white: 0.88).opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func verificationIcon(_ status: VerificationStatus) -> String {
        switch status {
        case .unverified: return "circle.dashed"
        case .pending:    return "clock.fill"
        case .verified:   return "checkmark.seal.fill"
        case .rejected:   return "xmark.seal.fill"
        }
    }

    private func verificationColor(_ status: VerificationStatus) -> Color {
        switch status {
        case .unverified: return Color(white: 0.65)
        case .pending:    return Color(red: 0.95, green: 0.75, blue: 0.0)
        case .verified:   return .black
        case .rejected:   return Color(red: 0.85, green: 0.20, blue: 0.20)
        }
    }

    private func verificationLabel(_ status: VerificationStatus) -> String {
        switch status {
        case .unverified: return "Unverified"
        case .pending:    return "Pending"
        case .verified:   return "Verified"
        case .rejected:   return "Rejected"
        }
    }

    private func verificationStatusDescription(_ status: VerificationStatus) -> String {
        switch status {
        case .unverified: return "Submit documents to begin verification."
        case .pending:    return "Your verification request is under review."
        case .verified:   return "Your account has been verified."
        case .rejected:   return "Verification was not approved. Please contact support."
        }
    }

    private func handleSave() {
        var updates: [String: Any] = [:]
        if accountType == .church {
            updates["displayName"] = churchDisplayName
            updates["bio"] = churchBio
            updates["websiteURL"] = churchWebsiteURL
            updates["livestreamURL"] = churchLivestreamURL
            updates["givingURL"] = churchGivingURL
            updates["phone"] = churchPhone
            updates["email"] = churchEmail
            updates["denomination"] = churchDenomination
            updates["address.street"] = addressStreet
            updates["address.city"] = addressCity
            updates["address.state"] = addressState
            updates["address.zip"] = addressZip
        } else {
            updates["displayName"] = businessDisplayName
            updates["bio"] = businessBio
            updates["websiteURL"] = businessWebsiteURL
            updates["contactEmail"] = businessContactEmail
            updates["category"] = businessCategory
            updates["missionStatement"] = businessMissionStatement
        }
        updates["username"] = username
        NotificationCenter.default.post(
            name: Notification.Name("AmenSaveAccountProfile"),
            object: nil,
            userInfo: ["updates": updates, "accountType": accountType.rawValue]
        )
        dismiss()
    }
}

// MARK: - Preview

struct ChurchEditProfileView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ChurchEditProfileView(accountType: .church)
                .previewDisplayName("Church Account")

            ChurchEditProfileView(accountType: .business)
                .previewDisplayName("Business Account")
        }
        .preferredColorScheme(.light)
    }
}
