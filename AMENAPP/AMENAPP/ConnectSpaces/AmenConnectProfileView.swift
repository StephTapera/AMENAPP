// AmenConnectProfileView.swift
// AMEN Connect — Profile (identity that serves the body)
//
// Slack profiles answer "who is this and how do I reach them."
// Amen profiles also answer "how is this person knit into the body,
// and where can they serve / be served?"
//
// Sections:
//   Photo · Name · Role · Organization · Covenant Presence · Status
//   Spiritual Gifts · Ministries · Availability (service matching)
//   Contact Information · Affiliations
//
// Service matching: Berean finds people nearby marked Available
// whose gifts/skills match a need — privately, opt-in, never auto-volunteering anyone.

import SwiftUI
import FirebaseAuth

// MARK: - Profile model

struct AmenConnectUserProfile: Identifiable {
    let id: String
    var displayName: String
    var username: String
    var role: String
    var organization: String
    var bio: String
    var email: String?
    var locationLabel: String?
    var spiritualGifts: [String]
    var ministries: [String]
    var skills: [String]
    var availability: AmenServiceAvailability
    var covenantPresence: AmenConnectSpacesSpiritualState
    var isOwnProfile: Bool
    var affiliations: [String]
}

struct AmenServiceAvailability {
    var isAvailable: Bool
    var availableDays: [String]
    var preferredService: [String]
    var maxDistanceKm: Int
}

// MARK: - ViewModel

@MainActor
final class AmenConnectProfileViewModel: ObservableObject {
    @Published var profile: AmenConnectUserProfile
    @Published var showEditProfile: Bool = false
    @Published var showPresencePicker: Bool = false
    @Published var showServiceMatch: Bool = false

    init(profile: AmenConnectUserProfile? = nil) {
        self.profile = profile ?? AmenConnectProfileViewModel.currentUserProfile()
    }

    static func currentUserProfile() -> AmenConnectUserProfile {
        let user = Auth.auth().currentUser
        let name = user?.displayName ?? "Amen Member"
        return AmenConnectUserProfile(
            id: user?.uid ?? "local",
            displayName: name,
            username: name.lowercased().replacingOccurrences(of: " ", with: ""),
            role: "",
            organization: "",
            bio: "",
            email: user?.email,
            locationLabel: nil,
            spiritualGifts: [],
            ministries: [],
            skills: [],
            availability: AmenServiceAvailability(
                isAvailable: false,
                availableDays: [],
                preferredService: [],
                maxDistanceKm: 10
            ),
            covenantPresence: .inTheWord,
            isOwnProfile: true,
            affiliations: []
        )
    }

    var presenceLabel: String {
        switch profile.covenantPresence {
        case .inTheWord:              return "📖 In the Word"
        case .inPrayer:               return "🙏 In Prayer"
        case .fasting:                return "✨ Fasting"
        case .sabbathRest:            return "🌙 Sabbath Rest"
        case .grieving:               return "💙 Grieving"
        case .discerning:             return "🕊️ Discerning"
        case .availableForUrgentPrayer: return "🔴 Available for Urgent Prayer"
        }
    }

    var presenceColor: Color {
        switch profile.covenantPresence {
        case .sabbathRest, .grieving: return Color.amenBlue
        case .inPrayer, .discerning: return Color.amenPurple
        default: return Color.accentColor
        }
    }
}

// MARK: - Main View

struct AmenConnectProfileView: View {
    @StateObject private var vm: AmenConnectProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scrollOffset: CGFloat = 0

    init(profile: AmenConnectUserProfile? = nil) {
        _vm = StateObject(wrappedValue: AmenConnectProfileViewModel(profile: profile))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                contentBody
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .sheet(isPresented: $vm.showPresencePicker) {
            AmenSpiritualPresencePickerView()
        }
        .sheet(isPresented: $vm.showEditProfile) {
            AmenEditConnectProfileView(profile: $vm.profile)
        }
        .sheet(isPresented: $vm.showServiceMatch) {
            AmenServiceMatchSheet(profile: vm.profile)
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        ZStack(alignment: .bottom) {
            // Gradient backdrop
            LinearGradient(
                colors: [
                    Color(uiColor: .secondarySystemGroupedBackground),
                    Color(uiColor: .systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)

            VStack(spacing: 0) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color.amenPurple.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Text(vm.profile.displayName.prefix(2).uppercased())
                        .font(.title.weight(.bold))
                        .foregroundStyle(Color.amenPurple)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(vm.presenceColor)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 2))
                }
                .padding(.top, 24)
                .accessibilityHidden(true)

                // Name
                Text(vm.profile.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.top, 12)
                    .accessibilityAddTraits(.isHeader)

                // Role
                if !vm.profile.role.isEmpty {
                    Text(vm.profile.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Organization
                if !vm.profile.organization.isEmpty {
                    Text(vm.profile.organization)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 1)
                }

                // Presence badge
                presenceBadge
                    .padding(.top, 10)

                // Action buttons
                actionButtons
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
    }

    private var presenceBadge: some View {
        Button {
            if vm.profile.isOwnProfile { vm.showPresencePicker = true }
        } label: {
            Text(vm.presenceLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(vm.presenceColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(vm.presenceColor.opacity(0.12))
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!vm.profile.isOwnProfile)
        .accessibilityLabel("Spiritual presence: \(vm.presenceLabel)\(vm.profile.isOwnProfile ? ". Tap to change." : "")")
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if vm.profile.isOwnProfile {
                profileButton("Set a Status", icon: "circle.dotted") {
                    vm.showPresencePicker = true
                }
                profileButton("Edit Profile", icon: "pencil") {
                    vm.showEditProfile = true
                }
            } else {
                profileButton("Pray", icon: "hands.sparkles") {}
                profileButton("Message", icon: "bubble.left") {}
            }
        }
        .padding(.horizontal, 24)
    }

    private func profileButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Content sections

    private var contentBody: some View {
        VStack(spacing: 16) {
            // Bio
            if !vm.profile.bio.isEmpty {
                bioSection
            }
            // Spiritual Gifts
            if !vm.profile.spiritualGifts.isEmpty || vm.profile.isOwnProfile {
                spiritualGiftsSection
            }
            // Ministries
            if !vm.profile.ministries.isEmpty || vm.profile.isOwnProfile {
                ministriesSection
            }
            // Availability & Service Matching
            availabilitySection
            // Contact Info
            if vm.profile.isOwnProfile || vm.profile.email != nil {
                contactInfoSection
            }
            // Affiliations
            if !vm.profile.affiliations.isEmpty {
                affiliationsSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 40)
    }

    // MARK: Bio

    private var bioSection: some View {
        profileCard {
            Text(vm.profile.bio)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Spiritual Gifts

    private var spiritualGiftsSection: some View {
        profileCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Spiritual Gifts", icon: "sparkles", accent: Color.amenPurple)
                if vm.profile.spiritualGifts.isEmpty {
                    emptyFieldRow("Add your spiritual gifts", action: { vm.showEditProfile = true })
                } else {
                    ChipRow(items: vm.profile.spiritualGifts, accent: Color.amenPurple)
                }
            }
        }
    }

    // MARK: Ministries

    private var ministriesSection: some View {
        profileCard {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Ministries", icon: "building.columns", accent: Color.accentColor)
                if vm.profile.ministries.isEmpty {
                    emptyFieldRow("Add your ministry areas", action: { vm.showEditProfile = true })
                } else {
                    ChipRow(items: vm.profile.ministries, accent: Color.accentColor)
                }
            }
        }
    }

    // MARK: Availability & Service Matching

    private var availabilitySection: some View {
        profileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("Availability", icon: "calendar.badge.checkmark", accent: .green)
                    Spacer()
                    Circle()
                        .fill(vm.profile.availability.isAvailable ? Color.green : Color(uiColor: .systemGray3))
                        .frame(width: 10, height: 10)
                    Text(vm.profile.availability.isAvailable ? "Available" : "Not available")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(vm.profile.availability.isAvailable ? .green : .secondary)
                }

                if !vm.profile.availability.preferredService.isEmpty {
                    Text("Serves in: " + vm.profile.availability.preferredService.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Berean service matching CTA
                if vm.profile.availability.isAvailable {
                    Button {
                        vm.showServiceMatch = true
                    } label: {
                        Label("Find service opportunities near you", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Berean: find service opportunities matching your gifts near you")
                } else if vm.profile.isOwnProfile {
                    emptyFieldRow("Mark yourself available to serve", action: { vm.showEditProfile = true })
                }
            }
        }
    }

    // MARK: Contact Info

    private var contactInfoSection: some View {
        profileCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("Contact Information", icon: "envelope", accent: Color(uiColor: .systemGray))
                    Spacer()
                    if vm.profile.isOwnProfile {
                        Button("Edit") { vm.showEditProfile = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let email = vm.profile.email {
                    Label(email, systemImage: "envelope")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let loc = vm.profile.locationLabel {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Affiliations

    private var affiliationsSection: some View {
        profileCard {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Affiliations", icon: "person.3", accent: Color(uiColor: .systemGray))
                ForEach(vm.profile.affiliations, id: \.self) { aff in
                    Text(aff)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func profileCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sectionHeader(_ title: String, icon: String, accent: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent)
            .accessibilityAddTraits(.isHeader)
    }

    private func emptyFieldRow(_ placeholder: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(!vm.profile.isOwnProfile)
        .accessibilityLabel(placeholder)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Edit Profile", systemImage: "pencil") { vm.showEditProfile = true }
                Button("Share Profile", systemImage: "square.and.arrow.up") {}
                Divider()
                Button("Report", systemImage: "flag", role: .destructive) {}
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More options")
            }
        }
    }
}

// MARK: - Chip row (spiritual gifts / ministries)

private struct ChipRow: View {
    let items: [String]
    let accent: Color

    var body: some View {
        // Simple wrapping layout using a flow-like approach
        VStack(alignment: .leading, spacing: 6) {
            let rows = chunked(items, size: 3)
            ForEach(rows.indices, id: \.self) { ri in
                HStack(spacing: 6) {
                    ForEach(rows[ri], id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(0.10))
                            .clipShape(Capsule(style: .continuous))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(items.joined(separator: ", "))
    }

    private func chunked(_ arr: [String], size: Int) -> [[String]] {
        stride(from: 0, to: arr.count, by: size).map {
            Array(arr[$0..<min($0 + size, arr.count)])
        }
    }
}

// MARK: - Service Match sheet (Berean powered)

private struct AmenServiceMatchSheet: View {
    let profile: AmenConnectUserProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.amenPurple)
                    .padding(.top, 40)
                Text("Berean is looking for opportunities that match your gifts")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Text("Berean finds people nearby marked Available whose gifts and skills match a need — privately, opt-in. It never auto-volunteers you; it only offers and you confirm.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                ProgressView()
                    .padding(.top, 8)
                Spacer()
            }
            .navigationTitle("Service Matching")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Edit profile sheet (stub — wires to real editor in production)

private struct AmenEditConnectProfileView: View {
    @Binding var profile: AmenConnectUserProfile
    @Environment(\.dismiss) private var dismiss

    @State private var draftRole: String = ""
    @State private var draftOrg: String = ""
    @State private var draftBio: String = ""
    @State private var draftGifts: String = ""
    @State private var draftMinistries: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Role (e.g. Worship Leader)", text: $draftRole)
                    TextField("Organization", text: $draftOrg)
                }
                Section("Bio") {
                    TextField("Say something about yourself", text: $draftBio, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Spiritual Gifts") {
                    TextField("Comma-separated (e.g. Teaching, Helps, Mercy)", text: $draftGifts)
                }
                Section("Ministries") {
                    TextField("Comma-separated (e.g. Worship, Youth, Care)", text: $draftMinistries)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .onAppear {
                draftRole = profile.role
                draftOrg  = profile.organization
                draftBio  = profile.bio
                draftGifts = profile.spiritualGifts.joined(separator: ", ")
                draftMinistries = profile.ministries.joined(separator: ", ")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        profile.role = draftRole
                        profile.organization = draftOrg
                        profile.bio = draftBio
                        profile.spiritualGifts = draftGifts
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        profile.ministries = draftMinistries
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AmenConnectProfileView(
            profile: AmenConnectUserProfile(
                id: "preview",
                displayName: "Marcus Williams",
                username: "marcusw",
                role: "Worship Leader",
                organization: "Cornerstone Church",
                bio: "Passionate about worship, discipleship, and seeing people encounter God.",
                email: "marcus@church.com",
                locationLabel: "Atlanta, GA",
                spiritualGifts: ["Teaching", "Helps", "Mercy", "Leadership"],
                ministries: ["Worship", "Small Groups", "Youth"],
                skills: ["Guitar", "Audio Engineering"],
                availability: AmenServiceAvailability(
                    isAvailable: true,
                    availableDays: ["Saturday", "Sunday"],
                    preferredService: ["Music", "Hospitality"],
                    maxDistanceKm: 15
                ),
                covenantPresence: .inTheWord,
                isOwnProfile: false,
                affiliations: ["Cornerstone Church — Worship Team", "City Prayer Network"]
            )
        )
    }
}
