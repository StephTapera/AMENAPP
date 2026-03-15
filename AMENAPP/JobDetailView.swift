// JobDetailView.swift
// AMENAPP
//
// Full job detail page with employer info, job description,
// apply flows (external / AMEN Easy Apply / Express Interest),
// save, share, and safety disclaimers.

import SwiftUI
import SafariServices

// MARK: - Apply Sheet Type

enum JobApplySheetType: Identifiable {
    case easyApply(JobListing)
    case expressInterest(JobListing)
    case externalConfirm(url: String, jobTitle: String, employerName: String)

    var id: String {
        switch self {
        case .easyApply(let j): return "easy_\(j.id ?? "")"
        case .expressInterest(let j): return "express_\(j.id ?? "")"
        case .externalConfirm(let url, _, _): return "ext_\(url)"
        }
    }
}

// MARK: - Job Detail View

struct JobDetailView: View {
    let jobId: String
    var matchResult: JobMatchResult?    // optional: from recommendations

    @StateObject private var service = JobService.shared
    @State private var job: JobListing?
    @State private var employer: EmployerProfile?
    @State private var isLoading = true
    @State private var isSaved = false
    @State private var hasApplied = false
    @State private var applySheet: JobApplySheetType?
    @State private var showReportSheet = false
    @State private var showSafariURL: URL?

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if let job = job {
                jobContent(job)
            } else {
                errorView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let job = job {
                    saveButton(job)
                    moreButton(job)
                }
            }
        }
        .sheet(item: $applySheet) { sheet in
            applySheetContent(sheet)
        }
        .sheet(isPresented: $showReportSheet) {
            if let job = job {
                JobReportSheet(targetId: job.id ?? "", targetType: "job", jobTitle: job.title)
            }
        }
        .task {
            await loadJob()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading opportunity...")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("Opportunity not found")
                .font(.custom("OpenSans-SemiBold", size: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Content

    private func jobContent(_ job: JobListing) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Employer header
                employerHeader(job)

                Divider().padding(.horizontal, 16)

                // Job title block
                jobTitleBlock(job)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                // Why matched (if from recommendations)
                if let match = matchResult, !match.matchReasons.isEmpty {
                    whyMatchedBanner(match)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }

                Divider().padding(.horizontal, 16)

                // Job details grid
                jobDetailsGrid(job)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                Divider().padding(.horizontal, 16)

                // Description
                if !job.description.isEmpty {
                    jobSection(title: "About the Role") {
                        Text(job.description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.primary)
                            .lineSpacing(4)
                    }
                }

                // Requirements
                if !job.requirements.isEmpty {
                    jobSection(title: "Requirements") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(job.requirements, id: \.self) { req in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                                        .padding(.top, 1)
                                    Text(req)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }

                // Responsibilities
                if !job.responsibilities.isEmpty {
                    jobSection(title: "Responsibilities") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(job.responsibilities, id: \.self) { resp in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                                        .padding(.top, 1)
                                    Text(resp)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }

                // Benefits
                if !job.benefits.isEmpty {
                    jobSection(title: "Benefits") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(job.benefits, id: \.self) { benefit in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(red: 0.90, green: 0.65, blue: 0.20))
                                        .padding(.top, 2)
                                    Text(benefit)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }

                // About the employer
                if let emp = employer {
                    employerAboutSection(emp)
                }

                // Safety disclaimer
                safetyDisclaimer(job)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                // Bottom spacer for sticky bar
                Color.clear.frame(height: 100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            applyBottomBar(job)
        }
    }

    // MARK: - Employer Header

    private func employerHeader(_ job: JobListing) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(job.category.color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: job.category.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(job.category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(job.employerName)
                    .font(.custom("OpenSans-Bold", size: 15))
                    .foregroundStyle(.primary)
                if job.employerVerified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                        Text("Verified Employer")
                            .font(.custom("OpenSans-Regular", size: 11))
                    }
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                }
                if let emp = employer {
                    Text(emp.responseTimeLabel)
                        .font(.custom("OpenSans-Regular", size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: - Job Title Block

    private func jobTitleBlock(_ job: JobListing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(job.title)
                .font(.custom("OpenSans-Bold", size: 22))
                .foregroundStyle(.primary)

            // Type + arrangement + classification pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    JobTagPill(label: job.jobType.label, color: job.jobType.color)
                    JobTagPill(label: job.workArrangement.label, color: job.workArrangement.color)
                    JobTagPill(label: job.classification.label, color: job.classification.color)
                }
            }

            // Salary
            if job.compensationType != .undisclosed {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.25, green: 0.70, blue: 0.45))
                    Text(job.formattedSalary)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Why Matched Banner

    private func whyMatchedBanner(_ match: JobMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                Text("Why this matched")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                Spacer()
                Text("\(Int(match.overallScore * 100))% match")
                    .font(.custom("OpenSans-Bold", size: 12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color(red: 0.20, green: 0.55, blue: 0.95))
                    )
            }

            ForEach(match.matchReasons.prefix(3)) { reason in
                HStack(spacing: 8) {
                    Image(systemName: reason.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.35, green: 0.80, blue: 0.35))
                        .frame(width: 16)
                    Text(reason.text)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Details Grid

    private func jobDetailsGrid(_ job: JobListing) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let city = job.city {
                JobDetailCell(icon: "mappin.circle.fill", label: "Location", value: [city, job.state].compactMap { $0 }.joined(separator: ", "))
            }
            JobDetailCell(icon: job.workArrangement.icon, label: "Arrangement", value: job.workArrangement.label)
            JobDetailCell(icon: "star.fill", label: "Experience", value: job.experienceLevel.label)
            JobDetailCell(icon: job.jobType.icon, label: "Type", value: job.jobType.label)
            if let edu = job.educationRequirement, edu != .none {
                JobDetailCell(icon: "graduationcap.fill", label: "Education", value: edu.label)
            }
            if let deadline = job.applicationDeadline {
                JobDetailCell(icon: "calendar", label: "Deadline", value: deadline.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    // MARK: - Sections

    private func jobSection<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Employer About

    private func employerAboutSection(_ emp: EmployerProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                Text("About \(emp.organizationName)")
                    .font(.custom("OpenSans-Bold", size: 16))

                if !emp.description.isEmpty {
                    Text(emp.description)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(4)
                }

                HStack(spacing: 16) {
                    if let count = emp.employeeCount {
                        Label(count.label, systemImage: "person.2.fill")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Label(emp.organizationType.label, systemImage: emp.organizationType.icon)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }

                if let url = emp.websiteURL, !url.isEmpty {
                    Link(destination: URL(string: url) ?? URL(string: "https://amen.app")!) {
                        Label("Visit website", systemImage: "arrow.up.right.square")
                            .font(.custom("OpenSans-SemiBold", size: 13))
                            .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Safety Disclaimer

    private func safetyDisclaimer(_ job: JobListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Important Notice")
                        .font(.custom("OpenSans-SemiBold", size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("AMEN is not the employer for this role. Applying will share your profile, resume, and application answers with \(job.employerName). AMEN reviews listings but cannot guarantee every posting is legitimate. Report suspicious activity below.")
                    .font(.custom("OpenSans-Regular", size: 11))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .lineSpacing(3)

                Button("Report this listing") {
                    showReportSheet = true
                }
                .font(.custom("OpenSans-SemiBold", size: 11))
                .foregroundStyle(Color(red: 0.80, green: 0.35, blue: 0.35))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.secondary.opacity(0.06))
            )
        }
    }

    // MARK: - Bottom Bar

    private func applyBottomBar(_ job: JobListing) -> some View {
        HStack(spacing: 12) {
            // Save button
            Button {
                Task {
                    try? await service.saveJob(job.id ?? "", title: job.title, employer: job.employerName)
                    isSaved = true
                }
            } label: {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundStyle(isSaved ? Color(red: 0.20, green: 0.55, blue: 0.95) : .secondary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Apply CTA
            Button {
                handleApplyTap(job)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: job.applyModel.icon)
                        .font(.system(size: 15, weight: .semibold))
                    Text(hasApplied ? "Applied" : job.applyModel.ctaLabel)
                        .font(.custom("OpenSans-Bold", size: 15))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hasApplied ? Color(red: 0.35, green: 0.75, blue: 0.45) : Color(red: 0.20, green: 0.55, blue: 0.95))
                )
            }
            .disabled(hasApplied || job.isExpired)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Toolbar Buttons

    private func saveButton(_ job: JobListing) -> some View {
        Button {
            Task {
                try? await service.saveJob(job.id ?? "", title: job.title, employer: job.employerName)
                isSaved = true
            }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .foregroundStyle(isSaved ? Color(red: 0.20, green: 0.55, blue: 0.95) : .primary)
        }
    }

    private func moreButton(_ job: JobListing) -> some View {
        Menu {
            Button(role: .destructive) {
                showReportSheet = true
            } label: {
                Label("Report listing", systemImage: "exclamationmark.triangle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: - Apply Logic

    private func handleApplyTap(_ job: JobListing) {
        service.logJobView(jobId: job.id ?? "", surface: "detail")
        switch job.applyModel {
        case .externalApply:
            guard let url = job.externalApplyURL, !url.isEmpty else { return }
            applySheet = .externalConfirm(url: url, jobTitle: job.title, employerName: job.employerName)
        case .amenEasyApply:
            applySheet = .easyApply(job)
        case .expressInterest:
            applySheet = .expressInterest(job)
        }
    }

    // MARK: - Apply Sheet Content

    @ViewBuilder
    private func applySheetContent(_ sheet: JobApplySheetType) -> some View {
        switch sheet {
        case .easyApply(let job):
            AMENEasyApplyForm(job: job) {
                hasApplied = true
                applySheet = nil
            }
        case .expressInterest(let job):
            ExpressInterestForm(job: job) {
                hasApplied = true
                applySheet = nil
            }
        case .externalConfirm(let urlStr, let title, let employer):
            ExternalApplyConfirmation(
                jobTitle: title,
                employerName: employer,
                urlString: urlStr
            ) {
                applySheet = nil
            }
        }
    }

    // MARK: - Data Loading

    private func loadJob() async {
        isLoading = true
        defer { isLoading = false }

        async let jobFetch = service.fetchJob(id: jobId)
        let fetchedJob = await jobFetch
        job = fetchedJob

        if let j = fetchedJob {
            isSaved = service.isJobSaved(j.id ?? "")
            hasApplied = service.myApplications.contains { $0.jobId == j.id }
            employer = await service.fetchEmployerProfile(for: j.employerId)
            service.logJobView(jobId: j.id ?? "", surface: "detail")
        }
    }
}

// MARK: - Job Detail Cell

struct JobDetailCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.custom("OpenSans-Regular", size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - AMEN Easy Apply Form

struct AMENEasyApplyForm: View {
    let job: JobListing
    let onSubmit: () -> Void

    @StateObject private var service = JobService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var coverNote = ""
    @State private var portfolioURL = ""
    @State private var screeningAnswers: [String: String] = [:]
    @State private var hasConsented = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if didSubmit {
                        successView
                    } else {
                        applicationForm
                    }
                }
                .padding(16)
            }
            .navigationTitle("Easy Apply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
            Text("Application Submitted!")
                .font(.custom("OpenSans-Bold", size: 20))
            Text("Your application has been sent to \(job.employerName). You can track its status in Saved & Applied.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { onSubmit() }
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(red: 0.20, green: 0.55, blue: 0.95), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 40)
    }

    private var applicationForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Job header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(job.category.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: job.category.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(job.category.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                    Text(job.employerName)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Cover note
            VStack(alignment: .leading, spacing: 8) {
                Text("Cover Note (optional)")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                TextEditor(text: $coverNote)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .frame(height: 120)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.secondary.opacity(0.2), lineWidth: 0.5)
                    )
            }

            // Portfolio / work samples
            VStack(alignment: .leading, spacing: 8) {
                Text("Portfolio or Work Samples (optional)")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                TextField("https://yourportfolio.com", text: $portfolioURL)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            // Screening questions
            if !job.screeningQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Screening Questions")
                        .font(.custom("OpenSans-Bold", size: 15))
                    ForEach(job.screeningQuestions) { q in
                        screeningQuestionField(q)
                    }
                }
            }

            // Consent
            Toggle(isOn: $hasConsented) {
                Text("I consent to share my AMEN profile, resume, and this application with \(job.employerName). AMEN is not the employer.")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(CheckboxToggleStyle())

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(Color(red: 0.80, green: 0.35, blue: 0.35))
            }

            // Submit
            Button {
                Task { await submitApplication() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Submit Application")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(hasConsented ? Color(red: 0.20, green: 0.55, blue: 0.95) : Color.secondary.opacity(0.3))
                )
            }
            .disabled(!hasConsented || isSubmitting)
        }
    }

    @ViewBuilder
    private func screeningQuestionField(_ q: ScreeningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(q.question)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                if q.isRequired {
                    Text("*")
                        .foregroundStyle(Color(red: 0.80, green: 0.35, blue: 0.35))
                }
            }
            switch q.questionType {
            case .freeText:
                TextField("Your answer", text: Binding(
                    get: { screeningAnswers[q.id] ?? "" },
                    set: { screeningAnswers[q.id] = $0 }
                ))
                .font(.custom("OpenSans-Regular", size: 13))
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .yesNo:
                HStack(spacing: 12) {
                    ForEach(["Yes", "No"], id: \.self) { option in
                        Button {
                            screeningAnswers[q.id] = option
                        } label: {
                            Text(option)
                                .font(.custom("OpenSans-SemiBold", size: 13))
                                .foregroundStyle(screeningAnswers[q.id] == option ? .white : .primary)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        screeningAnswers[q.id] == option
                                        ? Color(red: 0.20, green: 0.55, blue: 0.95)
                                        : Color.secondary.opacity(0.12)
                                    )
                                )
                        }
                    }
                }
            case .multipleChoice:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(q.options ?? [], id: \.self) { opt in
                        Button {
                            screeningAnswers[q.id] = opt
                        } label: {
                            HStack {
                                Image(systemName: screeningAnswers[q.id] == opt ? "circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                                Text(opt)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            case .numeric:
                TextField("Enter number", text: Binding(
                    get: { screeningAnswers[q.id] ?? "" },
                    set: { screeningAnswers[q.id] = $0 }
                ))
                .font(.custom("OpenSans-Regular", size: 13))
                .keyboardType(.numberPad)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func submitApplication() async {
        guard let userId = service.mySeekerProfile?.userId ?? Auth.auth().currentUser?.uid else { return }
        isSubmitting = true
        errorMessage = nil

        let answers = job.screeningQuestions.map { q in
            ScreeningAnswer(questionId: q.id, answer: screeningAnswers[q.id] ?? "")
        }

        let application = JobApplication(
            jobId: job.id ?? "",
            jobTitle: job.title,
            employerId: job.employerId,
            applicantId: userId,
            applicantName: service.mySeekerProfile?.displayName ?? "Applicant",
            applyModel: .amenEasyApply,
            coverNote: coverNote.isEmpty ? nil : coverNote,
            resumeURL: service.mySeekerProfile?.resumeURL,
            portfolioURL: portfolioURL.isEmpty ? nil : portfolioURL,
            screeningAnswers: answers,
            status: .submitted,
            employerNotes: nil,
            isRead: false,
            consentToShareProfile: hasConsented,
            moderationState: .active,
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try await service.submitApplication(application)
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Express Interest Form

struct ExpressInterestForm: View {
    let job: JobListing
    let onSubmit: () -> Void

    @StateObject private var service = JobService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var hasConsented = false
    @State private var isSubmitting = false
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if didSubmit {
                    VStack(spacing: 16) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                        Text("Interest Sent!")
                            .font(.custom("OpenSans-Bold", size: 20))
                        Text("\(job.employerName) can now see your profile and reach out.")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Done") { onSubmit() }
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(red: 0.20, green: 0.55, blue: 0.95), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(24)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("A brief note (optional)")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                        TextEditor(text: $message)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .frame(height: 100)
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Toggle(isOn: $hasConsented) {
                            Text("Share my AMEN profile with \(job.employerName).")
                                .font(.custom("OpenSans-Regular", size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .toggleStyle(CheckboxToggleStyle())

                        Button {
                            Task { await submit() }
                        } label: {
                            Text(isSubmitting ? "Sending..." : "Express Interest")
                                .font(.custom("OpenSans-Bold", size: 15))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(hasConsented ? Color(red: 0.20, green: 0.55, blue: 0.95) : Color.secondary.opacity(0.3))
                                )
                        }
                        .disabled(!hasConsented || isSubmitting)
                    }
                    .padding(16)
                }
                Spacer()
            }
            .navigationTitle("Express Interest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        isSubmitting = true
        let application = JobApplication(
            jobId: job.id ?? "",
            jobTitle: job.title,
            employerId: job.employerId,
            applicantId: userId,
            applicantName: service.mySeekerProfile?.displayName ?? "User",
            applyModel: .expressInterest,
            coverNote: message.isEmpty ? nil : message,
            resumeURL: nil,
            portfolioURL: nil,
            screeningAnswers: [],
            status: .submitted,
            employerNotes: nil,
            isRead: false,
            consentToShareProfile: hasConsented,
            moderationState: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
        try? await service.submitApplication(application)
        didSubmit = true
        isSubmitting = false
    }
}

// MARK: - External Apply Confirmation

struct ExternalApplyConfirmation: View {
    let jobTitle: String
    let employerName: String
    let urlString: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))

                VStack(spacing: 8) {
                    Text("Leaving AMEN")
                        .font(.custom("OpenSans-Bold", size: 20))
                    Text("You're about to apply for \(jobTitle) on \(employerName)'s site. \(employerName)'s privacy policy governs their application process. AMEN is not the employer.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Button {
                        if let url = URL(string: urlString) {
                            UIApplication.shared.open(url)
                        }
                        onDismiss()
                    } label: {
                        Label("Continue to \(employerName)", systemImage: "arrow.up.right.square")
                            .font(.custom("OpenSans-Bold", size: 15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(red: 0.20, green: 0.55, blue: 0.95), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button("Cancel") { onDismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Report Sheet

struct JobReportSheet: View {
    let targetId: String
    let targetType: String
    let jobTitle: String

    @StateObject private var service = JobService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: JobModerationReason = .scamJob
    @State private var description = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false

    var body: some View {
        NavigationStack {
            if didSubmit {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.35, green: 0.75, blue: 0.45))
                    Text("Report Submitted")
                        .font(.custom("OpenSans-Bold", size: 18))
                    Text("Thank you. Our team will review this listing.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
                .padding(24)
            } else {
                Form {
                    Section("Reason") {
                        ForEach(JobModerationReason.allCases, id: \.self) { reason in
                            Button {
                                selectedReason = reason
                            } label: {
                                HStack {
                                    Text(reason.label)
                                        .font(.custom("OpenSans-Regular", size: 14))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedReason == reason {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                                    }
                                }
                            }
                        }
                    }

                    Section("Additional Details (optional)") {
                        TextEditor(text: $description)
                            .font(.custom("OpenSans-Regular", size: 14))
                            .frame(height: 80)
                    }
                }
                .navigationTitle("Report Listing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Submit") {
                            Task {
                                isSubmitting = true
                                try? await service.reportJob(
                                    jobId: targetId,
                                    reason: selectedReason,
                                    description: description.isEmpty ? nil : description
                                )
                                didSubmit = true
                                isSubmitting = false
                            }
                        }
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .disabled(isSubmitting)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Auth import for AMENEasyApplyForm

import FirebaseAuth
