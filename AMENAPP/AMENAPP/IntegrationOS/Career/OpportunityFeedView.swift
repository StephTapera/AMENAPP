// OpportunityFeedView.swift — AMEN IntegrationOS
// SwiftUI list of ministry and career opportunities.

import SwiftUI

@MainActor
final class OpportunityFeedViewModel: ObservableObject {
    @Published var opportunities: [JobOpportunity] = []
    @Published var selectedFilter: JobType?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showPostForm = false

    private let service = OpportunityService.shared

    func load() async {
        isLoading = true
        errorMessage = nil
        opportunities = (try? await service.fetchOpportunities(filter: selectedFilter)) ?? []
        isLoading = false
    }
}

struct OpportunityFeedView: View {
    @StateObject private var viewModel = OpportunityFeedViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.opportunities.isEmpty {
                    ProgressView("Loading opportunities…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.opportunities.isEmpty {
                    ContentUnavailableView(
                        "No Opportunities",
                        systemImage: "briefcase",
                        description: Text("Check back soon for ministry and career openings.")
                    )
                } else {
                    List {
                        filterPicker
                        ForEach(viewModel.opportunities) { opp in
                            NavigationLink(destination: OpportunityDetailView(opportunity: opp)) {
                                OpportunityRow(opportunity: opp)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Opportunities")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showPostForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $viewModel.showPostForm) {
                OpportunityPostFormView()
            }
            .onChange(of: viewModel.selectedFilter) {
                Task { await viewModel.load() }
            }
        }
    }

    private var filterPicker: some View {
        Section {
            Picker("Filter", selection: $viewModel.selectedFilter) {
                Text("All").tag(JobType?.none)
                ForEach(JobType.allCases, id: \.self) { type in
                    Text(type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(JobType?.some(type))
                }
            }
            .pickerStyle(.menu)
        }
    }
}

private struct OpportunityRow: View {
    let opportunity: JobOpportunity
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(opportunity.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(opportunity.jobType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            Text(opportunity.orgName)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(opportunity.isRemote ? "Remote" : opportunity.location, systemImage: "location")
                if let comp = opportunity.compensationRange {
                    Text("· \(comp)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct OpportunityDetailView: View {
    let opportunity: JobOpportunity
    @Environment(\.colorScheme) private var colorScheme
    @State private var showApplySheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(opportunity.title)
                    .font(.title2.weight(.bold))
                Text(opportunity.orgName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(opportunity.isRemote ? "Remote" : opportunity.location, systemImage: "location.fill")
                    Label(opportunity.jobType.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "briefcase.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(opportunity.description)
                    .font(.subheadline)

                if !opportunity.tags.isEmpty {
                    TagRow(tags: opportunity.tags)
                }

                Button {
                    showApplySheet = true
                } label: {
                    Text("Apply Now")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding()
        }
        .navigationTitle("Opportunity")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showApplySheet) {
            ApplySheet(opportunityId: opportunity.id, orgName: opportunity.orgName)
        }
    }
}

private struct TagRow: View {
    let tags: [String]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

private struct ApplySheet: View {
    let opportunityId: String
    let orgName: String
    @Environment(\.dismiss) private var dismiss
    @State private var coverNote = ""
    @State private var portfolioURL = ""
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cover Note") {
                    TextEditor(text: $coverNote)
                        .frame(minHeight: 100)
                }
                Section("Portfolio / LinkedIn") {
                    TextField("https://", text: $portfolioURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Apply to \(orgName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        Task {
                            isApplying = true
                            try? await OpportunityService.shared.apply(
                                opportunityId: opportunityId,
                                coverNote: coverNote.isEmpty ? nil : coverNote,
                                portfolioURL: portfolioURL.isEmpty ? nil : portfolioURL
                            )
                            isApplying = false
                            dismiss()
                        }
                    }
                    .disabled(isApplying)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct OpportunityPostFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var orgName = ""
    @State private var description = ""
    @State private var location = ""
    @State private var isRemote = false
    @State private var jobType: JobType = .volunteer
    @State private var isPosting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Job Title", text: $title)
                    TextField("Organization", text: $orgName)
                    Picker("Type", selection: $jobType) {
                        ForEach(JobType.allCases, id: \.self) {
                            Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                        }
                    }
                }
                Section("Location") {
                    Toggle("Remote", isOn: $isRemote)
                    if !isRemote {
                        TextField("Location", text: $location)
                    }
                }
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Post Opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        Task {
                            isPosting = true
                            let opp = JobOpportunity(
                                posterId: "",
                                orgId: nil,
                                orgName: orgName,
                                title: title,
                                description: description,
                                location: location,
                                isRemote: isRemote,
                                jobType: jobType,
                                ministryArea: nil,
                                compensationType: .volunteer,
                                compensationRange: nil,
                                tags: [],
                                applicationURL: nil,
                                contactEmail: nil,
                                expiresAt: nil,
                                createdAt: Date(),
                                isActive: true
                            )
                            try? await OpportunityService.shared.post(opportunity: opp)
                            isPosting = false
                            dismiss()
                        }
                    }
                    .disabled(title.isEmpty || orgName.isEmpty || isPosting)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
