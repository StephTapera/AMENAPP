// JobSeekerProfileView.swift
// AMENAPP
// Candidate profile + "Open to Work" management

import SwiftUI
import FirebaseAuth

// MARK: - Job Seeker Profile View

struct JobSeekerProfileView: View {
    @StateObject private var service = JobService.shared
    @Environment(\.dismiss) private var dismiss

    // Profile state
    @State private var headline: String = ""
    @State private var bio: String = ""
    @State private var skills: [String] = []
    @State private var experienceLevel: ExperienceLevel = .midLevel
    @State private var desiredJobTypes: Set<JobType> = []
    @State private var desiredArrangements: Set<WorkArrangement> = []
    @State private var desiredCategories: Set<JobCategory> = []
    @State private var desiredLocation: String = ""
    @State private var openToRelocate: Bool = false
    @State private var portfolioURL: String = ""
    @State private var compensationMin: Double? = nil
    @State private var compensationText: String = ""
    @State private var openToWorkEnabled: Bool = false
    @State private var visibility: OpenToWorkVisibility = .verifiedRecruitersOnly

    // UI state
    @State private var isEditMode: Bool = false
    @State private var isSaving: Bool = false
    @State private var showSkillPicker: Bool = false
    @State private var showPostLookingView: Bool = false
    @State private var saveError: String? = nil
    @State private var showDeleteConfirmation: Bool = false

    // Inline seeker skill input
    @State private var skillInput: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if service.mySeekerProfile == nil && !isEditMode {
                    emptyStateView
                } else {
                    profileScrollView
                }
            }
            .navigationTitle("Job Seeker Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if service.mySeekerProfile != nil {
                        Button(isEditMode ? "Save" : "Edit") {
                            if isEditMode {
                                Task { await saveProfile() }
                            } else {
                                isEditMode = true
                            }
                        }
                        .fontWeight(isEditMode ? .semibold : .regular)
                    }
                }
            }
            .sheet(isPresented: $showSkillPicker) {
                SkillPickerSheet(selectedSkills: $skills)
            }
            .sheet(isPresented: $showPostLookingView) {
                PostLookingForWorkView { profile in
                    loadProfileIntoState(profile)
                    service.mySeekerProfile = profile
                    isEditMode = false
                }
            }
            .alert("Delete Profile?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task { await deleteProfile() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove your job seeker profile and Open to Work status. Recruiters will no longer see you.")
            }
            .onAppear {
                Task { await loadProfile() }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "briefcase.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Text("Create Your Job Seeker Profile")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text("Let faith-aligned employers and ministries discover your skills. Control who sees your profile at all times.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button {
                    showPostLookingView = true
                } label: {
                    Label("I'm Open to Work", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    isEditMode = true
                    // Pre-fill open to work
                    openToWorkEnabled = true
                } label: {
                    Label("Build Full Profile", systemImage: "person.text.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Profile Scroll View

    private var profileScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Open to Work Card
                openToWorkCard
                    .padding(.horizontal)
                    .padding(.top, 16)

                Divider().padding(.vertical, 8)

                // Visibility
                if openToWorkEnabled || service.mySeekerProfile?.isActive == true {
                    visibilitySection
                        .padding(.horizontal)

                    Divider().padding(.vertical, 8)
                }

                // Headline
                headlineSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Skills
                skillsSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Experience
                experienceSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Desired Job Types
                desiredJobTypesSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Work Arrangement
                arrangementSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Location
                locationSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Compensation
                compensationSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Portfolio
                portfolioSection
                    .padding(.horizontal)

                Divider().padding(.vertical, 8)

                // Save/error actions
                if isEditMode {
                    actionSection
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                } else if service.mySeekerProfile != nil {
                    deleteSection
                        .padding(.horizontal)
                        .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Open to Work Card

    private var openToWorkCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Open to Work", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .foregroundStyle(openToWorkEnabled ? .green : .primary)
                    Text(openToWorkEnabled
                         ? "Your profile is visible to employers"
                         : "Enable to let employers find you")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isEditMode {
                    Toggle("", isOn: $openToWorkEnabled)
                        .labelsHidden()
                } else {
                    Image(systemName: openToWorkEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(openToWorkEnabled ? .green : .secondary)
                        .font(.title3)
                }
            }

            if openToWorkEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(visibility.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Visibility Section

    private var visibilitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile Visibility")
                .font(.subheadline.bold())

            if isEditMode {
                ForEach(OpenToWorkVisibility.allCases) { level in
                    Button {
                        visibility = level
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: visibility == level ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(visibility == level ? Color.accentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: visibility.icon)
                        .foregroundStyle(Color.accentColor)
                    Text(visibility.label)
                        .font(.subheadline)
                    Text("—")
                        .foregroundStyle(.secondary)
                    Text(visibility.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Headline Section

    private var headlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Professional Headline")
                .font(.subheadline.bold())

            if isEditMode {
                TextField("e.g. Youth Pastor | Seeking Full-Time Ministry Role", text: $headline, axis: .vertical)
                    .lineLimit(2...3)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(headline.isEmpty ? "Add a headline to stand out" : headline)
                    .font(.subheadline)
                    .foregroundStyle(headline.isEmpty ? .tertiary : .primary)
            }
        }
    }

    // MARK: - Skills Section

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Skills")
                    .font(.subheadline.bold())
                Spacer()
                if isEditMode {
                    Button("Browse") { showSkillPicker = true }
                        .font(.caption)
                }
            }

            if skills.isEmpty && !isEditMode {
                Text("No skills added yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowTagView(tags: skills, isEditable: isEditMode) { tag in
                    skills.removeAll { $0 == tag }
                }
            }

            if isEditMode {
                HStack {
                    TextField("Add a skill...", text: $skillInput)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Button {
                        let trimmed = skillInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !skills.contains(trimmed) {
                            skills.append(trimmed)
                        }
                        skillInput = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                    }
                    .disabled(skillInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Experience Section

    private var experienceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Experience Level")
                .font(.subheadline.bold())

            if isEditMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExperienceLevel.allCases) { level in
                            Button {
                                experienceLevel = level
                            } label: {
                                Text(level.label)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        experienceLevel == level ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(experienceLevel == level ? .white : .primary)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(experienceLevel.label)
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Desired Job Types

    private var desiredJobTypesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job Types I'm Interested In")
                .font(.subheadline.bold())

            if isEditMode {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(JobType.allCases) { jobType in
                        JobTypeToggleCell(
                            jobType: jobType,
                            isSelected: desiredJobTypes.contains(jobType),
                            onTap: {
                                if desiredJobTypes.contains(jobType) { desiredJobTypes.remove(jobType) }
                                else { desiredJobTypes.insert(jobType) }
                            }
                        )
                    }
                }
            } else {
                if desiredJobTypes.isEmpty {
                    Text("No preferences set")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    FlowTagView(tags: desiredJobTypes.map(\.label), isEditable: false) { _ in }
                }
            }
        }
    }

    // MARK: - Arrangement Section

    private var arrangementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Work Arrangement")
                .font(.subheadline.bold())

            HStack(spacing: 8) {
                ForEach(WorkArrangement.allCases) { arrangement in
                    ArrangementToggleButton(
                        arrangement: arrangement,
                        isSelected: desiredArrangements.contains(arrangement),
                        isEnabled: isEditMode,
                        onTap: {
                            if isEditMode {
                                if desiredArrangements.contains(arrangement) { desiredArrangements.remove(arrangement) }
                                else { desiredArrangements.insert(arrangement) }
                            }
                        }
                    )
                }
                Spacer()
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.subheadline.bold())

            if isEditMode {
                VStack(spacing: 8) {
                    TextField("City, State (e.g. Atlanta, GA)", text: $desiredLocation)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Toggle("Open to relocation", isOn: $openToRelocate)
                        .font(.subheadline)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(desiredLocation.isEmpty ? "Not specified" : desiredLocation)
                        .font(.subheadline)
                        .foregroundStyle(desiredLocation.isEmpty ? .tertiary : .primary)

                    if openToRelocate {
                        Text("· Open to relocate")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    // MARK: - Compensation Section

    private var compensationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Minimum Desired Compensation")
                .font(.subheadline.bold())

            if isEditMode {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("e.g. 45000", text: $compensationText)
                        .keyboardType(.numberPad)
                    Text("/ year")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("This is visible to recruiters as a range indicator, not an exact figure.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let comp = compensationMin {
                        Text("$\(Int(comp).formatted()) / year minimum")
                            .font(.subheadline)
                    } else {
                        Text("Not specified")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Portfolio Section

    private var portfolioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio / Website")
                .font(.subheadline.bold())

            if isEditMode {
                TextField("https://yoursite.com", text: $portfolioURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(portfolioURL.isEmpty ? "Not added" : portfolioURL)
                        .font(.subheadline)
                        .foregroundStyle(portfolioURL.isEmpty ? Color(UIColor.tertiaryLabel) : Color.accentColor)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 12) {
            if let error = saveError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                Task { await saveProfile() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text("Save Profile")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(isSaving)

            Button("Cancel") {
                isEditMode = false
                if let existing = service.mySeekerProfile {
                    loadProfileIntoState(existing)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        VStack {
            Divider()
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Remove Job Seeker Profile", systemImage: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
    }

    // MARK: - Load / Save

    private func loadProfile() async {
        if let uid = Auth.auth().currentUser?.uid {
            service.mySeekerProfile = await service.fetchSeekerProfile(for: uid)
        }
        if let profile = service.mySeekerProfile {
            loadProfileIntoState(profile)
        }
    }

    private func loadProfileIntoState(_ profile: JobSeekerProfile) {
        headline = profile.headline
        bio = profile.bio
        skills = profile.skills
        experienceLevel = profile.experienceLevel
        desiredJobTypes = Set(profile.desiredJobTypes)
        desiredArrangements = Set(profile.desiredArrangements)
        desiredCategories = Set(profile.desiredCategories)
        desiredLocation = profile.desiredLocation ?? ""
        openToRelocate = profile.openToRelocate
        portfolioURL = profile.portfolioURL ?? ""
        compensationMin = profile.desiredCompensationMin
        compensationText = profile.desiredCompensationMin.map { "\(Int($0))" } ?? ""
        openToWorkEnabled = profile.isActive
        visibility = profile.openToWorkVisibility
    }

    private func saveProfile() async {
        isSaving = true
        saveError = nil

        guard let uid = Auth.auth().currentUser?.uid else {
            saveError = "You must be signed in to save your profile."
            isSaving = false
            return
        }

        let compValue = Double(compensationText.filter { $0.isNumber })

        var profile = service.mySeekerProfile ?? JobSeekerProfile(
            userId: uid,
            displayName: Auth.auth().currentUser?.displayName ?? "",
            headline: "",
            bio: "",
            avatarURL: nil,
            resumeURL: nil,
            portfolioURL: nil,
            skills: [],
            experienceLevel: .midLevel,
            desiredJobTypes: [],
            desiredCategories: [],
            desiredArrangements: [],
            desiredCompensationMin: nil,
            desiredLocation: nil,
            openToRelocate: false,
            openToWorkVisibility: .verifiedRecruitersOnly,
            isActive: false,
            trustScore: 1.0,
            moderationState: .active,
            searchKeywords: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        profile.headline = headline
        profile.bio = bio
        profile.skills = skills
        profile.experienceLevel = experienceLevel
        profile.desiredJobTypes = Array(desiredJobTypes)
        profile.desiredArrangements = Array(desiredArrangements)
        profile.desiredCategories = Array(desiredCategories)
        profile.desiredLocation = desiredLocation.isEmpty ? nil : desiredLocation
        profile.openToRelocate = openToRelocate
        profile.portfolioURL = portfolioURL.isEmpty ? nil : portfolioURL
        profile.desiredCompensationMin = compValue
        profile.openToWorkVisibility = visibility
        profile.isActive = openToWorkEnabled
        profile.updatedAt = Date()

        do {
            try await service.saveSeekerProfile(profile)
            service.mySeekerProfile = profile
            isEditMode = false
        } catch {
            saveError = error.localizedDescription
        }

        isSaving = false
    }

    private func deleteProfile() async {
        try? await service.deleteSeekerProfile()
        dismiss()
    }
}

// MARK: - Flow Tag View (reusable chip layout)

struct FlowTagView: View {
    let tags: [String]
    let isEditable: Bool
    let onRemove: (String) -> Void

    var body: some View {
        // SwiftUI flow layout using ViewThatFits approximation
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80, maximum: 180))],
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.caption)
                        .lineLimit(1)
                    if isEditable {
                        Button {
                            onRemove(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            }
        }
    }
}

// MARK: - Skill Picker Sheet

struct SkillPickerSheet: View {
    @Binding var selectedSkills: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private let predefinedSkills: [String: [String]] = [
        "Ministry & Pastoral": [
            "Preaching", "Teaching", "Pastoral Care", "Discipleship", "Counseling",
            "Small Group Leadership", "Evangelism", "Biblical Studies", "Theology",
            "Youth Ministry", "Children's Ministry", "Women's Ministry", "Men's Ministry"
        ],
        "Worship & Creative": [
            "Worship Leading", "Guitar", "Piano/Keys", "Bass", "Drums", "Vocals",
            "Sound Engineering", "ProPresenter", "Graphic Design", "Video Production",
            "Photography", "Motion Graphics", "Live Streaming"
        ],
        "Administration & Operations": [
            "Church Administration", "Nonprofit Management", "Event Planning",
            "Volunteer Coordination", "Project Management", "Budget Management",
            "HR Management", "Facilities Management", "Data Entry", "Microsoft Office"
        ],
        "Technology": [
            "Web Development", "iOS Development", "Android Development", "Python",
            "JavaScript", "React", "Swift", "Database Management", "IT Support",
            "Network Administration", "Cybersecurity"
        ],
        "Communications": [
            "Social Media Management", "Content Writing", "Copywriting",
            "Email Marketing", "SEO", "Public Relations", "Newsletter Management",
            "Podcast Production", "Blogging"
        ],
        "Education & Counseling": [
            "Teaching", "Curriculum Development", "Special Education",
            "School Administration", "Mental Health Counseling", "Marriage Counseling",
            "Addiction Counseling", "Crisis Intervention"
        ],
        "Social Work & Missions": [
            "Community Outreach", "Social Work", "Case Management",
            "Overseas Missions", "Church Planting", "Language Translation",
            "Humanitarian Aid", "Chaplaincy"
        ]
    ]

    var filteredSkills: [String: [String]] {
        if searchText.isEmpty { return predefinedSkills }
        var result: [String: [String]] = [:]
        for (category, skills) in predefinedSkills {
            let filtered = skills.filter { $0.localizedCaseInsensitiveContains(searchText) }
            if !filtered.isEmpty { result[category] = filtered }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSkills.keys.sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(filteredSkills[category] ?? [], id: \.self) { skill in
                            SkillPickerRow(
                                skill: skill,
                                isSelected: selectedSkills.contains(skill),
                                onTap: {
                                    if selectedSkills.contains(skill) {
                                        selectedSkills.removeAll { $0 == skill }
                                    } else {
                                        selectedSkills.append(skill)
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search skills")
            .navigationTitle("Select Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Post Looking For Work View (quick flow)

struct PostLookingForWorkView: View {
    let onComplete: (JobSeekerProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var headline: String = ""
    @State private var skills: [String] = []
    @State private var selectedJobTypes: Set<JobType> = []
    @State private var visibility: OpenToWorkVisibility = .verifiedRecruitersOnly
    @State private var isSubmitting: Bool = false
    @State private var skillInput: String = ""

    var canProceed: Bool {
        !headline.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Let Employers Find You", systemImage: "hand.raised.fill")
                            .font(.title2.bold())
                        Text("Fill in a few details to signal that you're open to opportunities. You can update this anytime.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Headline
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Headline *")
                            .font(.subheadline.bold())
                        TextField("e.g. Worship Leader | Available for Ministry Roles", text: $headline, axis: .vertical)
                            .lineLimit(2...3)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // Job Types
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interested In")
                            .font(.subheadline.bold())

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach([JobType.fullTime, .partTime, .contract, .volunteer, .ministryStaff, .churchStaff]) { type in
                                JobTypeToggleCell(
                                    jobType: type,
                                    isSelected: selectedJobTypes.contains(type),
                                    onTap: {
                                        if selectedJobTypes.contains(type) { selectedJobTypes.remove(type) }
                                        else { selectedJobTypes.insert(type) }
                                    }
                                )
                            }
                        }
                    }

                    // A couple skills
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Key Skills")
                            .font(.subheadline.bold())

                        HStack {
                            TextField("Add skill", text: $skillInput)
                                .padding(10)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button {
                                let s = skillInput.trimmingCharacters(in: .whitespaces)
                                if !s.isEmpty && !skills.contains(s) { skills.append(s) }
                                skillInput = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .disabled(skillInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        if !skills.isEmpty {
                            FlowTagView(tags: skills, isEditable: true) { tag in skills.removeAll { $0 == tag } }
                        }
                    }

                    // Visibility
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Who Can See Your Profile?")
                            .font(.subheadline.bold())

                        ForEach(OpenToWorkVisibility.allCases) { level in
                            let isSelected = visibility == level
                            Button {
                                visibility = level
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(level.label)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Text(level.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                                .background(
                                    isSelected
                                    ? Color.accentColor.opacity(0.08)
                                    : Color(.systemBackground).opacity(0),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                        }
                    }

                    // Submit
                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().progressViewStyle(.circular)
                            } else {
                                Text("Start Looking for Opportunities")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(
                            canProceed ? Color.accentColor : Color.secondary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .disabled(!canProceed || isSubmitting)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Open to Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        guard let uid = Auth.auth().currentUser?.uid else { isSubmitting = false; return }

        let profile = JobSeekerProfile(
            userId: uid,
            displayName: Auth.auth().currentUser?.displayName ?? "",
            headline: headline,
            bio: "",
            avatarURL: nil,
            resumeURL: nil,
            portfolioURL: nil,
            skills: skills,
            experienceLevel: .midLevel,
            desiredJobTypes: Array(selectedJobTypes),
            desiredCategories: [],
            desiredArrangements: [],
            desiredCompensationMin: nil,
            desiredLocation: nil,
            openToRelocate: false,
            openToWorkVisibility: visibility,
            isActive: true,
            trustScore: 1.0,
            moderationState: .active,
            searchKeywords: skills + [headline],
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try await JobService.shared.saveSeekerProfile(profile)
            onComplete(profile)
            dismiss()
        } catch {
            // silently fail — the caller can show an error if needed
        }
        isSubmitting = false
    }
}

// MARK: - Helper Cell Views

private struct JobTypeToggleCell: View {
    let jobType: JobType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.caption)
                Text(jobType.label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct ArrangementToggleButton: View {
    let arrangement: WorkArrangement
    let isSelected: Bool
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: arrangement.icon)
                    .font(.caption2)
                Text(arrangement.label)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .disabled(!isEnabled)
    }
}

private struct SkillPickerRow: View {
    let skill: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(skill)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    JobSeekerProfileView()
}
#endif
