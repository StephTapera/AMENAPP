// JobSavedAndAppliedView.swift
// AMENAPP
// Saved jobs, applied jobs tracker, and job alerts

import SwiftUI

// MARK: - Main View

struct JobSavedAndAppliedView: View {
    @StateObject private var service = JobService.shared
    @State private var selectedTab: SavedAppliedTab = .saved
    @State private var showCreateAlert: Bool = false

    enum SavedAppliedTab: String, CaseIterable {
        case saved = "Saved"
        case applied = "Applied"
        case alerts = "Alerts"

        var icon: String {
            switch self {
            case .saved:   return "bookmark.fill"
            case .applied: return "paperplane.fill"
            case .alerts:  return "bell.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(SavedAppliedTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider()

                // Tab Content
                Group {
                    switch selectedTab {
                    case .saved:   savedTab
                    case .applied: appliedTab
                    case .alerts:  alertsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == .alerts {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCreateAlert = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateAlert) {
                CreateJobAlertSheet()
            }
            .onAppear {
                // Saved jobs are loaded via real-time listener in JobService.setupListeners()
            }
        }
    }

    // MARK: - Saved Tab

    private var savedTab: some View {
        Group {
            if service.mySavedJobs.isEmpty {
                emptyState(
                    icon: "bookmark",
                    title: "No Saved Jobs",
                    message: "Tap the bookmark on any job to save it for later."
                )
            } else {
                List {
                    ForEach(service.mySavedJobs) { saved in
                        NavigationLink(destination: JobDetailView(jobId: saved.jobId)) {
                            SavedJobRow(saved: saved)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { try? await service.unsaveJob(saved.id ?? "") }
                            } label: {
                                Label("Remove", systemImage: "bookmark.slash.fill")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Applied Tab

    private var appliedTab: some View {
        Group {
            if service.myApplications.isEmpty {
                emptyState(
                    icon: "paperplane",
                    title: "No Applications Yet",
                    message: "When you apply to jobs through AMEN, your applications will appear here."
                )
            } else {
                List {
                    // Active applications
                    let active = service.myApplications.filter { $0.status != .withdrawn && $0.status != .expired }
                    let inactive = service.myApplications.filter { $0.status == .withdrawn || $0.status == .expired }

                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active) { application in
                                ApplicationTrackerCard(application: application)
                                    .swipeActions(edge: .trailing) {
                                        if application.status == .submitted || application.status == .viewed {
                                            Button(role: .destructive) {
                                                Task { try? await service.withdrawApplication(application.id ?? "") }
                                            } label: {
                                                Label("Withdraw", systemImage: "xmark.circle.fill")
                                            }
                                        }
                                    }
                            }
                        }
                    }

                    if !inactive.isEmpty {
                        Section("Past") {
                            ForEach(inactive) { application in
                                ApplicationTrackerCard(application: application)
                                    .opacity(0.7)
                            }
                        }
                    }
                }
                .listStyle(.grouped)
            }
        }
    }

    // MARK: - Alerts Tab

    private var alertsTab: some View {
        Group {
            if service.myJobAlerts.isEmpty {
                emptyState(
                    icon: "bell.slash",
                    title: "No Job Alerts",
                    message: "Create alerts to get notified when new matching jobs are posted."
                )
            } else {
                List {
                    ForEach(service.myJobAlerts) { alert in
                        JobAlertCard(alert: alert)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { try? await service.deleteJobAlert(alert.id ?? "") }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Empty State Helper

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
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

// MARK: - Saved Job Row

private struct SavedJobRow: View {
    let saved: SavedJob

    var body: some View {
        HStack(spacing: 12) {
            // Logo placeholder
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "briefcase.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.subheadline)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(saved.jobTitle)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(saved.employerName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Saved \(saved.savedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Application Tracker Card

struct ApplicationTrackerCard: View {
    let application: JobApplication

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(application.status.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: application.status.icon)
                            .foregroundStyle(application.status.color)
                            .font(.subheadline)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(application.jobTitle)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(application.employerId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                applicationStatusPill(application.status)
            }

            // Status Timeline
            statusTimeline(for: application.status)

            // Date
            Text("Applied \(application.createdAt.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func applicationStatusPill(_ status: ApplicationStatus) -> some View {
        Text(status.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15), in: Capsule())
            .foregroundStyle(status.color)
    }

    private func statusTimeline(for current: ApplicationStatus) -> some View {
        let stages: [ApplicationStatus] = [.submitted, .viewed, .shortlisted, .interviewing, .offered]
        let currentIndex = stages.firstIndex(of: current) ?? 0

        return HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                HStack(spacing: 0) {
                    Circle()
                        .fill(index <= currentIndex ? stage.color : Color.secondary.opacity(0.25))
                        .frame(width: 10, height: 10)
                        .overlay {
                            if index <= currentIndex {
                                Circle().stroke(Color.white, lineWidth: 1.5)
                                    .scaleEffect(1.4)
                            }
                        }

                    if index < stages.count - 1 {
                        Rectangle()
                            .fill(index < currentIndex ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 4)
    }
}

// MARK: - Job Alert Card

private struct JobAlertCard: View {
    let alert: JobAlert
    @StateObject private var service = JobService.shared
    @State private var isActive: Bool

    init(alert: JobAlert) {
        self.alert = alert
        _isActive = State(initialValue: alert.isActive)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.title3)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.alertName)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !alert.keywords.isEmpty {
                        Text(alert.keywords.prefix(2).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !alert.categories.isEmpty {
                        Text("· \(alert.categories.count) categories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("\(alert.frequency.label) updates")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: $isActive)
                .labelsHidden()
                .onChange(of: isActive) { _, newVal in
                    Task { try? await service.updateJobAlert(alert.id ?? "", isActive: newVal) }
                }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Job Category Toggle Row (extracted to help type checker)

private struct JobCategoryToggleRow: View {
    let category: JobCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label(category.label, systemImage: category.icon)
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

// MARK: - Create Job Alert Sheet

struct CreateJobAlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = JobService.shared

    @State private var alertName: String = ""
    @State private var keywords: String = ""
    @State private var selectedCategories: Set<JobCategory> = []
    @State private var selectedJobTypes: Set<JobType> = []
    @State private var selectedArrangements: Set<WorkArrangement> = []
    @State private var frequency: AlertFrequency = .daily
    @State private var location: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    var canCreate: Bool {
        !alertName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Alert Name") {
                    TextField("e.g. Youth Pastor in Atlanta", text: $alertName)
                }

                Section("Keywords") {
                    TextField("worship, youth ministry, nonprofit...", text: $keywords)
                    Text("Separate multiple keywords with commas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Job Categories") {
                    ForEach(JobCategory.allCases) { category in
                        JobCategoryToggleRow(
                            category: category,
                            isSelected: selectedCategories.contains(category)
                        ) {
                            if selectedCategories.contains(category) {
                                selectedCategories.remove(category)
                            } else {
                                selectedCategories.insert(category)
                            }
                        }
                    }
                }

                Section("Job Types") {
                    ForEach(JobType.allCases) { type in
                        let selected = selectedJobTypes.contains(type)
                        Button {
                            if selected { selectedJobTypes.remove(type) }
                            else { selectedJobTypes.insert(type) }
                        } label: {
                            HStack {
                                Text(type.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }

                Section("Location (Optional)") {
                    TextField("City, State", text: $location)
                }

                Section("Alert Frequency") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(AlertFrequency.allCases) { freq in
                            Text(freq.label).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create Job Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task { await createAlert() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate || isCreating)
                }
            }
        }
    }

    private func createAlert() async {
        isCreating = true
        errorMessage = nil

        let keywordList = keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let alert = JobAlert(
            userId: "",  // filled in by service
            alertName: alertName,
            keywords: keywordList,
            categories: Array(selectedCategories),
            jobTypes: Array(selectedJobTypes),
            arrangements: Array(selectedArrangements),
            location: location.isEmpty ? nil : location,
            isActive: true,
            frequency: frequency,
            createdAt: Date()
        )

        do {
            try await service.createJobAlert(alert)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    JobSavedAndAppliedView()
}
#endif
