// JobRecruiterDashboardView.swift
// AMENAPP
// Recruiter/employer dashboard: inbox, posted jobs, analytics, employer profile

import SwiftUI
import FirebaseAuth

// MARK: - Recruiter Dashboard

struct JobRecruiterDashboardView: View {
    @StateObject private var service = JobService.shared
    @State private var selectedTab: RecruiterTab = .applications
    @State private var showPostJob: Bool = false
    @State private var showEmployerProfileEditor: Bool = false

    enum RecruiterTab: String, CaseIterable {
        case applications = "Inbox"
        case myJobs       = "My Jobs"
        case analytics    = "Analytics"
        case profile      = "Profile"

        var icon: String {
            switch self {
            case .applications: return "tray.full.fill"
            case .myJobs:       return "list.bullet.rectangle.fill"
            case .analytics:    return "chart.bar.fill"
            case .profile:      return "building.2.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom tab bar
                tabBar
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Divider()

                // Content
                Group {
                    switch selectedTab {
                    case .applications: applicationsTab
                    case .myJobs:       myJobsTab
                    case .analytics:    analyticsTab
                    case .profile:      profileTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Recruiter Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == .myJobs {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showPostJob = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                if selectedTab == .profile {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Edit") {
                            showEmployerProfileEditor = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showPostJob) {
                JobPostingView()
            }
            .sheet(isPresented: $showEmployerProfileEditor) {
                EmployerProfileEditor()
            }
            .onAppear {
                Task {
                    if let uid = Auth.auth().currentUser?.uid {
                        service.myEmployerProfile = await service.fetchEmployerProfile(for: uid)
                    }
                }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(RecruiterTab.allCases, id: \.self) { tab in
                tabBarButton(for: tab)
            }
        }
    }

    @ViewBuilder
    private func tabBarButton(for tab: RecruiterTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                tabBarIcon(for: tab)
                Text(tab.rawValue)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func tabBarIcon(for tab: RecruiterTab) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: tab.icon)
                .font(.system(size: 18))
            if tab == .applications && service.unreadApplicationCount > 0 {
                Text("\(service.unreadApplicationCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.red, in: Circle())
                    .offset(x: 8, y: -6)
            }
        }
    }

    // MARK: - Applications Inbox Tab

    private var applicationsTab: some View {
        Group {
            if service.candidateInbox.isEmpty {
                recruiterEmptyState(
                    icon: "tray",
                    title: "No Applications Yet",
                    message: "Applications to your job postings will appear here."
                )
            } else {
                // Group by job
                let grouped = Dictionary(grouping: service.candidateInbox, by: \.jobId)
                List {
                    ForEach(Array(grouped.keys.sorted()), id: \.self) { jobId in
                        let apps = grouped[jobId] ?? []
                        let jobTitle = apps.first?.jobTitle ?? "Unknown Job"
                        let unread = apps.filter { !$0.isRead }.count

                        Section {
                            ForEach(apps) { application in
                                RecruiterInboxCard(application: application)
                            }
                        } header: {
                            HStack {
                                Text(jobTitle)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                if unread > 0 {
                                    Text("\(unread) new")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                Spacer()
                                Text("\(apps.count) applicants")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.grouped)
            }
        }
    }

    // MARK: - My Jobs Tab

    private var myJobsTab: some View {
        Group {
            if service.myPostedJobs.isEmpty {
                VStack(spacing: 20) {
                    recruiterEmptyState(
                        icon: "briefcase",
                        title: "No Jobs Posted",
                        message: "Post your first job to start finding faith-aligned talent."
                    )

                    Button {
                        showPostJob = true
                    } label: {
                        Label("Post a Job", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            } else {
                List {
                    let activeJobs = service.myPostedJobs.filter { $0.isActive }
                    let inactiveJobs = service.myPostedJobs.filter { !$0.isActive }

                    if !activeJobs.isEmpty {
                        Section("Active (\(activeJobs.count))") {
                            ForEach(activeJobs) { job in
                                RecruiterJobCard(job: job)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            Task { try? await service.deactivateJob(job.id ?? "") }
                                        } label: {
                                            Label("Deactivate", systemImage: "pause.circle.fill")
                                        }
                                        .tint(.orange)
                                    }
                            }
                        }
                    }

                    if !inactiveJobs.isEmpty {
                        Section("Inactive / Expired") {
                            ForEach(inactiveJobs) { job in
                                RecruiterJobCard(job: job)
                                    .opacity(0.6)
                            }
                        }
                    }
                }
                .listStyle(.grouped)
            }
        }
    }

    // MARK: - Analytics Tab

    private var analyticsTab: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Aggregate stats
                aggregateStatsGrid

                Divider().padding(.horizontal)

                // Per-job breakdown
                if !service.myPostedJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Per Job Breakdown")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(service.myPostedJobs) { job in
                            RecruiterJobAnalyticsRow(job: job)
                                .padding(.horizontal)
                        }
                    }
                } else {
                    recruiterEmptyState(
                        icon: "chart.bar",
                        title: "No Data Yet",
                        message: "Post jobs to see performance analytics."
                    )
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
    }

    private var aggregateStatsGrid: some View {
        let totalViews = service.myPostedJobs.reduce(0) { $0 + $1.viewCount }
        let totalApps = service.myPostedJobs.reduce(0) { $0 + $1.applicationCount }
        let totalSaves = service.myPostedJobs.reduce(0) { $0 + $1.saveCount }
        let conversionRate = totalViews > 0 ? Double(totalApps) / Double(totalViews) * 100 : 0.0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            RecruiterStatCell(label: "Total Views", value: "\(totalViews)", icon: "eye.fill", color: .blue)
            RecruiterStatCell(label: "Applications", value: "\(totalApps)", icon: "paperplane.fill", color: .green)
            RecruiterStatCell(label: "Saves", value: "\(totalSaves)", icon: "bookmark.fill", color: .orange)
            RecruiterStatCell(label: "Conversion", value: String(format: "%.1f%%", conversionRate), icon: "arrow.up.right.circle.fill", color: .purple)
        }
        .padding(.horizontal)
    }

    // MARK: - Profile Tab

    private var profileTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let employer = service.myEmployerProfile {
                    employerProfileDisplay(employer)
                } else {
                    VStack(spacing: 16) {
                        recruiterEmptyState(
                            icon: "building.2",
                            title: "No Employer Profile",
                            message: "Create a profile to attract faith-aligned candidates."
                        )
                        Button("Create Employer Profile") {
                            showEmployerProfileEditor = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private func employerProfileDisplay(_ employer: EmployerProfile) -> some View {
        VStack(spacing: 16) {
            // Header card
            VStack(spacing: 12) {
                // Logo
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 72, height: 72)
                    .overlay {
                        Image(systemName: "building.2.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(employer.organizationName)
                            .font(.title3.bold())
                        if employer.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    Text(employer.organizationType.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let location = employer.location, !location.isEmpty {
                        Label(location, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Subscription tier
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription Plan")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(employer.subscriptionTier.label)
                        .font(.subheadline.bold())
                }
                Spacer()
                Text(employer.subscriptionTier.monthlyPrice == 0 ? "Free" : "$\(String(format: "%.0f", employer.subscriptionTier.monthlyPrice))/mo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Performance stats
            VStack(alignment: .leading, spacing: 12) {
                Text("Performance")
                    .font(.subheadline.bold())

                HStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("\(employer.activeJobCount)")
                            .font(.title2.bold())
                        Text("Active Jobs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 40)
                    VStack(spacing: 4) {
                        Text("\(employer.totalHires)")
                            .font(.title2.bold())
                        Text("Total Hires")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider().frame(height: 40)
                    VStack(spacing: 4) {
                        Text(String(format: "%.0f%%", employer.responseRate * 100))
                            .font(.title2.bold())
                        Text("Response Rate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Description
            if !employer.description.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("About")
                        .font(.subheadline.bold())
                    Text(employer.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Helpers

    private func recruiterEmptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }
}

// MARK: - Recruiter Inbox Card

struct RecruiterInboxCard: View {
    let application: JobApplication
    @StateObject private var service = JobService.shared
    @State private var showStatusPicker: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(application.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)

            // Avatar placeholder
            Circle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(application.applicantName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(application.applicantName)
                    .font(.subheadline.bold())
                Text("Applied \(application.createdAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note = application.coverNote, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Status menu
            Menu {
                ForEach(ApplicationStatus.allCases) { status in
                    Button(status.label) {
                        Task {
                            try? await service.updateApplicationStatus(
                                application.id ?? "",
                                status: status
                            )
                        }
                    }
                }
            } label: {
                Text(application.status.label)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(application.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(application.status.color)
            }
        }
        .padding(.vertical, 4)
        .onTapGesture {
            if !application.isRead {
                Task { await service.markApplicationRead(application.id ?? "") }
            }
        }
    }
}

// MARK: - Recruiter Job Card

private struct RecruiterJobCard: View {
    let job: JobListing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    if !job.isActive {
                        Text("Inactive")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Label(job.workArrangement.label, systemImage: job.workArrangement.icon)
                    Label(job.jobType.label, systemImage: job.jobType.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("\(job.viewCount)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2)
                    Text("\(job.applicationCount)")
                        .font(.caption2)
                }
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Recruiter Analytics Row

private struct RecruiterJobAnalyticsRow: View {
    let job: JobListing

    var conversionRate: Double {
        job.viewCount > 0 ? Double(job.applicationCount) / Double(job.viewCount) * 100 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.title)
                .font(.subheadline.bold())
                .lineLimit(1)

            HStack(spacing: 12) {
                analyticsChip(value: "\(job.viewCount)", label: "Views", color: .blue)
                analyticsChip(value: "\(job.applicationCount)", label: "Applies", color: .green)
                analyticsChip(value: "\(job.saveCount)", label: "Saves", color: .orange)
                analyticsChip(value: String(format: "%.1f%%", conversionRate), label: "Conv.", color: .purple)
            }

            // Progress bar for conversion rate
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(conversionRate > 10 ? Color.green : conversionRate > 5 ? Color.orange : Color.red)
                        .frame(width: geo.size.width * min(conversionRate / 20, 1.0), height: 6)
                        .animation(.spring(response: 0.5), value: conversionRate)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func analyticsChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Recruiter Stat Cell

private struct RecruiterStatCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Employer Profile Editor

struct EmployerProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = JobService.shared

    @State private var orgName: String = ""
    @State private var orgType: EmployerType = .church
    @State private var description: String = ""
    @State private var websiteURL: String = ""
    @State private var location: String = ""
    @State private var employeeCount: EmployeeCount = .small2to10
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Organization") {
                    TextField("Organization Name", text: $orgName)
                    Picker("Type", selection: $orgType) {
                        ForEach(EmployerType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                }

                Section("About") {
                    TextEditor(text: $description)
                        .frame(minHeight: 80)
                }

                Section("Contact & Location") {
                    TextField("Website URL", text: $websiteURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("Location (City, State)", text: $location)
                }

                Section("Organization Size") {
                    Picker("Team Size", selection: $employeeCount) {
                        ForEach(EmployeeCount.allCases) { count in
                            Text(count.label).tag(count)
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Employer Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(orgName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let existing = service.myEmployerProfile {
                    orgName = existing.organizationName
                    orgType = existing.organizationType
                    description = existing.description
                    websiteURL = existing.websiteURL ?? ""
                    location = existing.location ?? ""
                    employeeCount = existing.employeeCount ?? .small2to10
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "You must be signed in."
            isSaving = false
            return
        }

        var profile = service.myEmployerProfile ?? EmployerProfile(
            userId: uid,
            organizationName: "",
            organizationType: .church,
            description: "",
            logoURL: nil,
            bannerURL: nil,
            websiteURL: nil,
            location: nil,
            employeeCount: nil,
            isVerified: false,
            verificationLevel: .none,
            activeJobCount: 0,
            totalHires: 0,
            responseRate: 0,
            averageResponseDays: 0,
            subscriptionTier: .free,
            trustScore: 1.0,
            moderationState: .active,
            searchKeywords: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        profile.organizationName = orgName
        profile.organizationType = orgType
        profile.description = description
        profile.websiteURL = websiteURL.isEmpty ? nil : websiteURL
        profile.location = location.isEmpty ? nil : location
        profile.employeeCount = employeeCount
        profile.updatedAt = Date()

        do {
            try await service.saveEmployerProfile(profile)
            service.myEmployerProfile = profile
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    JobRecruiterDashboardView()
}
#endif
