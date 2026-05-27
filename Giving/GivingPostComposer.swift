import SwiftUI
import FirebaseFunctions

struct GivingPostComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var narrative = ""
    @State private var selectedOrg: OrganizationStub? = nil
    @State private var goalAmountText = ""
    @State private var isPosting = false
    @State private var showOrgPicker = false
    @State private var errorMessage: String? = nil

    private let functions = Functions.functions()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    narrativeSection
                    orgPickerSection
                    goalSection
                    previewSection
                }
                .padding(16)
            }
            .navigationTitle("Giving Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isPosting ? "Sharing..." : "Create & Share") {
                        Task { await createPost() }
                    }
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(canPost ? Color(red: 0.83, green: 0.69, blue: 0.22) : AmenTheme.Colors.textTertiary)
                    .disabled(!canPost || isPosting)
                }
            }
            .sheet(isPresented: $showOrgPicker) { OrganizationPickerView(selected: $selectedOrg) }
        }
    }

    private var canPost: Bool { !narrative.trimmingCharacters(in: .whitespaces).isEmpty && selectedOrg != nil }

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your giving story", systemImage: "heart.text.square.fill")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            TextEditor(text: $narrative)
                .font(.custom("OpenSans-Regular", size: 15))
                .frame(minHeight: 100)
                .padding(8)
                .background(AmenTheme.Colors.surfaceInput)
                .cornerRadius(10)
                .accessibilityLabel("Giving post narrative")
            Text("\(narrative.count)/500")
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var orgPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Organization")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            Button { showOrgPicker = true } label: {
                HStack {
                    if let org = selectedOrg {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                        Text(org.name)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(AmenTheme.Colors.textPrimary)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                        Text("Select an organization")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(AmenTheme.Colors.textTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(AmenTheme.Colors.textTertiary)
                }
                .padding(12)
                .background(AmenTheme.Colors.surfaceCard)
                .cornerRadius(10)
            }
            .accessibilityLabel(selectedOrg != nil ? "Selected organization: \(selectedOrg!.name)" : "Select an organization")
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Goal amount (optional)")
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(AmenTheme.Colors.textPrimary)
            HStack {
                Text("$").font(.custom("OpenSans-Regular", size: 16)).foregroundStyle(AmenTheme.Colors.textSecondary)
                TextField("0", text: $goalAmountText)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .keyboardType(.numberPad)
            }
            .padding(12)
            .background(AmenTheme.Colors.surfaceInput)
            .cornerRadius(10)
            .accessibilityLabel("Goal amount in dollars")
        }
    }

    private var previewSection: some View {
        Group {
            if !narrative.isEmpty, let org = selectedOrg {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.custom("OpenSans-Bold", size: 15))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                    GivingPostCard(post: GivingPost(
                        userId: "",
                        narrative: narrative,
                        organizationId: org.id ?? "",
                        organizationName: org.name,
                        goalAmount: Int(goalAmountText).map { $0 * 100 },
                        currentAmount: 0,
                        linkedVerses: [],
                        tags: org.category,
                        visibility: "public",
                        engagementHearts: 0,
                        engagementComments: 0,
                        engagementShares: 0
                    ))
                }
            }
        }
    }

    private func createPost() async {
        guard let org = selectedOrg else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            var params: [String: Any] = [
                "narrative": narrative,
                "organizationId": org.id ?? "",
            ]
            if let goal = Int(goalAmountText) { params["goalAmount"] = goal * 100 }
            _ = try await functions.httpsCallable("createGivingPost").call(params)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct OrganizationPickerView: View {
    @Binding var selected: OrganizationStub?
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let presetOrgs: [OrganizationStub] = [
        OrganizationStub(id: "compassion", name: "Compassion International", category: ["childSponsorship"], logoUrl: nil, website: nil, trustScore: 95, verified: nil),
        OrganizationStub(id: "samaritans", name: "Samaritan's Purse", category: ["disasterRelief"], logoUrl: nil, website: nil, trustScore: 92, verified: nil),
        OrganizationStub(id: "worldvision", name: "World Vision", category: ["humanitarian"], logoUrl: nil, website: nil, trustScore: 90, verified: nil),
        OrganizationStub(id: "salvation", name: "The Salvation Army", category: ["communityServices"], logoUrl: nil, website: nil, trustScore: 88, verified: nil),
    ]

    var filtered: [OrganizationStub] {
        searchText.isEmpty ? presetOrgs : presetOrgs.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { org in
                Button {
                    selected = org
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "building.columns.fill").foregroundStyle(Color(red: 0.83, green: 0.69, blue: 0.22))
                        VStack(alignment: .leading) {
                            Text(org.name).font(.custom("OpenSans-Bold", size: 14)).foregroundStyle(AmenTheme.Colors.textPrimary)
                            Text(org.category.first?.capitalized ?? "").font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(AmenTheme.Colors.textSecondary)
                        }
                        Spacer()
                        if let score = org.trustScore {
                            Text("\(score)")
                                .font(.custom("OpenSans-Bold", size: 12))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(score >= 80 ? Color.green : score >= 60 ? Color.orange : Color.red)
                                .cornerRadius(8)
                        }
                    }
                }
                .accessibilityLabel(org.name)
            }
            .searchable(text: $searchText, prompt: "Search organizations")
            .navigationTitle("Select Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.font(.custom("OpenSans-Regular", size: 16))
                }
            }
        }
    }
}
