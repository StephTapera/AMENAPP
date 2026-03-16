// JobSearchView.swift
// AMENAPP
//
// Main Jobs landing page: search, filters, match recommendations,
// featured jobs, church opportunities, volunteer opportunities.
// Embedded into AMENConnectView when selectedTab == .jobs.

import SwiftUI

// MARK: - Main Job Search View

struct JobSearchView: View {
    @StateObject private var service = JobService.shared
    @State private var searchText = ""
    @State private var filters = JobSearchFilters()
    @State private var showFilters = false
    @State private var selectedJob: String?     // jobId for navigation
    @State private var showPostJob = false
    @State private var showSeekerProfile = false
    @State private var showSavedAndApplied = false
    @State private var hasLoadedInitial = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    // Search bar
                    searchBarSection

                    // Active filter chips
                    if !filters.isEmpty {
                        activeFilterChipsSection
                    }

                    // Content
                    if !searchText.isEmpty || !filters.isEmpty {
                        searchResultsSection
                    } else {
                        landingContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    jobsHeaderTitle
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        savedAppliedButton
                        postJobButton
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                JobFilterSheet(filters: $filters)
            }
            .sheet(isPresented: $showPostJob) {
                JobPostingView()
            }
            .sheet(isPresented: $showSeekerProfile) {
                JobSeekerProfileView()
            }
            .sheet(isPresented: $showSavedAndApplied) {
                JobSavedAndAppliedView()
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedJob != nil },
                set: { if !$0 { selectedJob = nil } }
            )) {
                if let jobId = selectedJob {
                    JobDetailView(jobId: jobId)
                }
            }
        }
        .task {
            guard !hasLoadedInitial else { return }
            hasLoadedInitial = true
            service.setupListeners()
            // P0-C FIX: Use withTaskGroup instead of async let closures so child tasks
            // are properly cancelled when the parent .task is cancelled (view disappears).
            // The async let + inline closure pattern triggers swift_task_dealloc crashes.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = await service.fetchFeaturedJobs() }
                group.addTask { _ = await service.fetchRecentJobs() }
                group.addTask { _ = await service.fetchMatchRecommendations() }
            }
        }
    }

    // MARK: - Header

    private var jobsHeaderTitle: some View {
        Text("Jobs & Opportunities")
            .font(.custom("OpenSans-Bold", size: 17))
            .foregroundStyle(.primary)
    }

    private var savedAppliedButton: some View {
        Button {
            showSavedAndApplied = true
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
        }
    }

    private var postJobButton: some View {
        Button {
            showPostJob = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
        }
    }

    // MARK: - Search Bar

    private var searchBarSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Job title, keyword, or skill", text: $searchText)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button { searchText = ""; service.searchResults = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Filter button
            Button {
                showFilters = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if filters.activeFilterCount > 0 {
                        Text("\(filters.activeFilterCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color(red: 0.20, green: 0.55, blue: 0.95), in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty { service.searchResults = [] }
        }
    }

    // MARK: - Active Filter Chips

    private var activeFilterChipsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !filters.arrangements.isEmpty {
                    ForEach(Array(filters.arrangements), id: \.self) { arr in
                        JobActiveFilterChip(label: arr.label, icon: arr.icon) {
                            filters.arrangements.remove(arr)
                        }
                    }
                }
                if !filters.jobTypes.isEmpty {
                    ForEach(Array(filters.jobTypes), id: \.self) { type in
                        JobActiveFilterChip(label: type.label, icon: type.icon) {
                            filters.jobTypes.remove(type)
                        }
                    }
                }
                if !filters.categories.isEmpty {
                    ForEach(Array(filters.categories), id: \.self) { cat in
                        JobActiveFilterChip(label: cat.label, icon: cat.icon) {
                            filters.categories.remove(cat)
                        }
                    }
                }
                Button("Clear all") {
                    filters = JobSearchFilters()
                }
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(Color(red: 0.80, green: 0.35, blue: 0.35))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Landing Content

    private var landingContent: some View {
        VStack(spacing: 0) {
            // "Open to Work" entry point
            if service.mySeekerProfile == nil {
                openToWorkEntryCard
            }

            // Match recommendations
            if !service.matchRecommendations.isEmpty {
                JobSectionHeader(title: "Matched for You", subtitle: "Based on your profile")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(service.matchRecommendations.prefix(8)) { match in
                            JobMatchRecommendationCard(result: match) {
                                selectedJob = match.job.id
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }

            // Featured jobs
            if !service.featuredJobs.isEmpty {
                JobSectionHeader(title: "Featured Opportunities", subtitle: nil)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(service.featuredJobs.prefix(8)) { job in
                            FeaturedJobCard(job: job) {
                                selectedJob = job.id
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }

            // Church & Ministry section
            JobSectionHeader(title: "Church & Ministry", subtitle: "Serve the local church")
            JobMinistryQuickSection(onJobTap: { jobId in selectedJob = jobId })

            // Volunteer section
            JobSectionHeader(title: "Serve & Volunteer", subtitle: "Give your time and gifts")
            JobVolunteerQuickSection(onJobTap: { jobId in selectedJob = jobId })

            // All recent
            if !service.recentJobs.isEmpty {
                JobSectionHeader(title: "Recently Posted", subtitle: nil)
                LazyVStack(spacing: 10) {
                    ForEach(service.recentJobs.prefix(15)) { job in
                        JobListingCard(job: job, isSaved: service.isJobSaved(job.id ?? "")) {
                            selectedJob = job.id
                        } onSave: {
                            Task { try? await service.saveJob(job.id ?? "", title: job.title, employer: job.employerName) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }

            // Loading state
            if service.isLoadingJobs {
                ProgressView()
                    .padding(40)
            }
        }
    }

    // MARK: - Search Results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if service.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(40)
            } else if service.searchResults.isEmpty && !searchText.isEmpty {
                jobEmptySearchState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(service.searchResults) { job in
                        JobListingCard(job: job, isSaved: service.isJobSaved(job.id ?? "")) {
                            selectedJob = job.id
                        } onSave: {
                            Task { try? await service.saveJob(job.id ?? "", title: job.title, employer: job.employerName) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var jobEmptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No jobs found")
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.primary)
            Text("Try different keywords or adjust your filters.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(48)
    }

    // MARK: - Open to Work Entry

    private var openToWorkEntryCard: some View {
        Button {
            showSeekerProfile = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up your job seeker profile")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                    Text("Let opportunities find you")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Search Action

    private func performSearch() {
        isSearchFocused = false
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            _ = await service.searchJobs(query: searchText, filters: filters)
        }
    }
}

// MARK: - Section Header

struct JobSectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - Job Listing Card (full-width)

struct JobListingCard: View {
    let job: JobListing
    let isSaved: Bool
    let onTap: () -> Void
    let onSave: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Header: employer info
                HStack(spacing: 10) {
                    // Logo placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(job.category.color.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: job.category.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(job.category.color)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(job.employerName)
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if job.employerVerified {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 9))
                                Text("Verified")
                                    .font(.custom("OpenSans-Regular", size: 10))
                            }
                            .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                        }
                    }
                    Spacer()

                    // Save button
                    Button(action: onSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 15))
                            .foregroundStyle(isSaved ? Color(red: 0.20, green: 0.55, blue: 0.95) : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Job title
                Text(job.title)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                // Pills: type, arrangement, category
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        JobTagPill(label: job.jobType.label, color: job.jobType.color)
                        JobTagPill(label: job.workArrangement.label, color: job.workArrangement.color)
                        JobTagPill(label: job.classification.label, color: job.classification.color)
                    }
                }

                // Salary + location
                HStack(spacing: 12) {
                    if job.compensationType != .undisclosed {
                        Label(job.formattedSalary, systemImage: "dollarsign.circle")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let city = job.city {
                        Label(city, systemImage: "mappin")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    // Posted time
                    Text(relativeTime(job.createdAt))
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        if diff < 604800 { return "\(Int(diff / 86400))d ago" }
        return "\(Int(diff / 604800))w ago"
    }
}

// MARK: - Featured Job Card (horizontal scroll)

struct FeaturedJobCard: View {
    let job: JobListing
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Category icon + featured badge
                HStack {
                    ZStack {
                        Circle()
                            .fill(job.category.color.opacity(0.20))
                            .frame(width: 44, height: 44)
                        Image(systemName: job.category.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(job.category.color)
                    }
                    Spacer()
                    if job.isPromoted {
                        Text("Promoted")
                            .font(.custom("OpenSans-SemiBold", size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color(red: 0.80, green: 0.55, blue: 0.15))
                            )
                    } else {
                        Text("Featured")
                            .font(.custom("OpenSans-SemiBold", size: 9))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color(red: 0.20, green: 0.55, blue: 0.95))
                            )
                    }
                }

                Text(job.title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(job.employerName)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 6) {
                    JobTagPill(label: job.workArrangement.label, color: job.workArrangement.color)
                    Spacer()
                    if job.compensationType != .undisclosed && job.compensationType != .volunteer {
                        Text(job.formattedSalary)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(14)
            .frame(width: 200, height: 160)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(job.category.color.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Match Recommendation Card

struct JobMatchRecommendationCard: View {
    let result: JobMatchResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(result.job.category.color.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: result.job.category.icon)
                            .font(.system(size: 18))
                            .foregroundStyle(result.job.category.color)
                    }
                    Spacer()
                    // Match score pill
                    Text("\(Int(result.overallScore * 100))% match")
                        .font(.custom("OpenSans-Bold", size: 10))
                        .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.12))
                        )
                }

                Text(result.job.title)
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(result.job.employerName)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Why matched
                if let topReason = result.matchReasons.first {
                    HStack(spacing: 5) {
                        Image(systemName: topReason.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.35, green: 0.80, blue: 0.35))
                        Text(topReason.text)
                            .font(.custom("OpenSans-Regular", size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(14)
            .frame(width: 200, height: 170)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ministry Quick Section

struct JobMinistryQuickSection: View {
    let onJobTap: (String) -> Void
    @StateObject private var service = JobService.shared
    @State private var ministryJobs: [JobListing] = []

    var body: some View {
        Group {
            if ministryJobs.isEmpty && !service.isLoadingJobs {
                JobCategoryEmptyState(
                    icon: "building.columns.fill",
                    message: "No church roles posted yet.\nBe the first to share an opportunity."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ministryJobs.prefix(8)) { job in
                            FeaturedJobCard(job: job) { onJobTap(job.id ?? "") }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task {
            ministryJobs = await service.fetchChurchOpportunities(limit: 10)
        }
    }
}

// MARK: - Volunteer Quick Section

struct JobVolunteerQuickSection: View {
    let onJobTap: (String) -> Void
    @StateObject private var service = JobService.shared
    @State private var volunteerJobs: [JobListing] = []

    var body: some View {
        Group {
            if volunteerJobs.isEmpty && !service.isLoadingJobs {
                JobCategoryEmptyState(
                    icon: "hands.sparkles.fill",
                    message: "No volunteer opportunities yet.\nChurches and nonprofits can post here."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(volunteerJobs.prefix(8)) { job in
                            FeaturedJobCard(job: job) { onJobTap(job.id ?? "") }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .task {
            volunteerJobs = await service.fetchVolunteerOpportunities(limit: 10)
        }
    }
}

// MARK: - Filter Sheet

struct JobFilterSheet: View {
    @Binding var filters: JobSearchFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Job Types
                Section("Type") {
                    ForEach(JobType.allCases) { type in
                        Toggle(isOn: Binding(
                            get: { filters.jobTypes.contains(type) },
                            set: { if $0 { filters.jobTypes.insert(type) } else { filters.jobTypes.remove(type) } }
                        )) {
                            Label(type.label, systemImage: type.icon)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                    }
                }

                // Work Arrangement
                Section("Arrangement") {
                    ForEach(WorkArrangement.allCases) { arr in
                        Toggle(isOn: Binding(
                            get: { filters.arrangements.contains(arr) },
                            set: { if $0 { filters.arrangements.insert(arr) } else { filters.arrangements.remove(arr) } }
                        )) {
                            Label(arr.label, systemImage: arr.icon)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                    }
                }

                // Classification
                Section("Organization Type") {
                    ForEach(JobClassification.allCases) { cls in
                        Toggle(isOn: Binding(
                            get: { filters.classifications.contains(cls) },
                            set: { if $0 { filters.classifications.insert(cls) } else { filters.classifications.remove(cls) } }
                        )) {
                            Label(cls.label, systemImage: cls.icon)
                                .font(.custom("OpenSans-Regular", size: 14))
                        }
                    }
                }

                // Posted Within
                Section("Posted Within") {
                    ForEach(PostedWithin.allCases) { pw in
                        Button {
                            filters.postedWithin = filters.postedWithin == pw ? nil : pw
                        } label: {
                            HStack {
                                Text(pw.label)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if filters.postedWithin == pw {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                                }
                            }
                        }
                    }
                }

                // Clear
                Section {
                    Button("Clear All Filters") {
                        filters = JobSearchFilters()
                    }
                    .foregroundStyle(Color(red: 0.80, green: 0.35, blue: 0.35))
                    .font(.custom("OpenSans-SemiBold", size: 14))
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
        }
    }
}

// MARK: - Helper Components

struct JobTagPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.custom("OpenSans-SemiBold", size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }
}

struct JobActiveFilterChip: View {
    let label: String
    let icon: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 11))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct JobCategoryEmptyState: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(message)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
