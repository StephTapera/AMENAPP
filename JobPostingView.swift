// JobPostingView.swift
// AMENAPP
//
// Multi-step job posting form for employers/churches/recruiters.
// 3 steps: Basic Info -> Details -> Apply Settings + Review.
// Integrates with JobService and JobSafetyEngine.

import SwiftUI
import FirebaseAuth

struct JobPostingView: View {
    @StateObject private var service = JobService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0

    // Step 1: Basic Info
    @State private var title = ""
    @State private var description = ""
    @State private var jobType: JobType = .fullTime
    @State private var classification: JobClassification = .christianOrg
    @State private var arrangement: WorkArrangement = .onSite
    @State private var category: JobCategory = .pastoralMinistry

    // Step 2: Details
    @State private var requirementText = ""
    @State private var requirements: [String] = []
    @State private var experienceLevel: ExperienceLevel = .midLevel
    @State private var compensationType: CompensationType = .salaried
    @State private var salaryMin = ""
    @State private var salaryMax = ""
    @State private var salaryPeriod: SalaryPeriod = .annual
    @State private var city = ""
    @State private var state = ""
    @State private var benefitText = ""
    @State private var benefits: [String] = []

    // Step 3: Apply Settings
    @State private var applyModel: ApplyModel = .amenEasyApply
    @State private var externalURL = ""
    @State private var postingTier: JobPostingTier = .free

    // Safety / submission state
    @State private var safetyWarning: String?
    @State private var isSubmitting = false
    @State private var didPost = false
    @State private var errorMessage: String?

    private let stepTitles = ["Basic Info", "Details", "Apply & Review"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepProgressBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                Divider()
                ScrollView {
                    if didPost {
                        successView
                    } else {
                        stepContent
                            .padding(16)
                    }
                }
                if !didPost {
                    navigationBar
                }
            }
            .navigationTitle("Post a Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Step Progress

    private var stepProgressBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<stepTitles.count, id: \.self) { i in
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(i <= step ? Color(red: 0.20, green: 0.55, blue: 0.95) : Color.secondary.opacity(0.2))
                            .frame(width: 24, height: 24)
                        if i < step {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(i == step ? .white : .secondary)
                        }
                    }
                    if i < stepTitles.count - 1 {
                        Rectangle()
                            .fill(i < step ? Color(red: 0.20, green: 0.55, blue: 0.95) : Color.secondary.opacity(0.2))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: step1View
        case 1: step2View
        default: step3View
        }
    }

    // MARK: - Step 1

    private var step1View: some View {
        VStack(alignment: .leading, spacing: 20) {
            JobFormField(label: "Job Title *") {
                TextField("e.g. Worship Pastor", text: $title)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            JobFormField(label: "Description * (min 20 chars)") {
                ZStack(alignment: .topLeading) {
                    if description.isEmpty {
                        Text("Describe the role, mission, and who you're looking for...")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .padding(14)
                    }
                    TextEditor(text: $description)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .frame(height: 130)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            JobFormField(label: "Job Type") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(JobType.allCases) { type in
                            Button { jobType = type } label: {
                                Text(type.label)
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                                    .foregroundStyle(jobType == type ? .white : type.color)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(jobType == type ? type.color : type.color.opacity(0.12)))
                            }
                        }
                    }
                }
            }
            JobFormField(label: "Work Arrangement") {
                HStack(spacing: 8) {
                    ForEach(WorkArrangement.allCases) { arr in
                        Button { arrangement = arr } label: {
                            Label(arr.label, systemImage: arr.icon)
                                .font(.custom("OpenSans-SemiBold", size: 12))
                                .foregroundStyle(arrangement == arr ? .white : .primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(arrangement == arr ? arr.color : Color.secondary.opacity(0.1))
                                )
                        }
                    }
                    Spacer()
                }
            }
            JobFormField(label: "Organization Type") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(JobClassification.allCases) { cls in
                            Button { classification = cls } label: {
                                Text(cls.label)
                                    .font(.custom("OpenSans-SemiBold", size: 11))
                                    .foregroundStyle(classification == cls ? .white : cls.color)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(classification == cls ? cls.color : cls.color.opacity(0.12)))
                            }
                        }
                    }
                }
            }
            JobFormField(label: "Category") {
                Picker("Category", selection: $category) {
                    ForEach(JobCategory.allCases) { cat in
                        Label(cat.label, systemImage: cat.icon).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Step 2

    private var step2View: some View {
        VStack(alignment: .leading, spacing: 20) {
            JobFormField(label: "Requirements") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Add a requirement", text: $requirementText)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        Button {
                            let trimmed = requirementText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { requirements.append(trimmed); requirementText = "" }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                        }
                    }
                    ForEach(requirements, id: \.self) { req in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(red: 0.20, green: 0.70, blue: 0.45))
                            Text(req).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.primary)
                            Spacer()
                            Button { requirements.removeAll { $0 == req } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            JobFormField(label: "Experience Level") {
                Picker("Experience", selection: $experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { lvl in
                        Text(lvl.label).tag(lvl)
                    }
                }
                .pickerStyle(.menu)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            JobFormField(label: "Compensation") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Type", selection: $compensationType) {
                        ForEach([CompensationType.salaried, .hourly, .stipend, .volunteer, .negotiable, .undisclosed], id: \.self) { ct in
                            Text(ct.label).tag(ct)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    if compensationType == .salaried || compensationType == .hourly || compensationType == .stipend {
                        HStack(spacing: 10) {
                            TextField("Min", text: $salaryMin)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .keyboardType(.decimalPad)
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            Text("–").foregroundStyle(.secondary)
                            TextField("Max", text: $salaryMax)
                                .font(.custom("OpenSans-Regular", size: 13))
                                .keyboardType(.decimalPad)
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            Picker("Period", selection: $salaryPeriod) {
                                ForEach(SalaryPeriod.allCases) { p in
                                    Text(p.shortLabel).tag(p)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            if arrangement != .remote {
                JobFormField(label: "Location") {
                    HStack(spacing: 10) {
                        TextField("City", text: $city)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        TextField("State / Region", text: $state)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            JobFormField(label: "Benefits (optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Add a benefit", text: $benefitText)
                            .font(.custom("OpenSans-Regular", size: 13))
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        Button {
                            let trimmed = benefitText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty { benefits.append(trimmed); benefitText = "" }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                        }
                    }
                    ForEach(benefits, id: \.self) { b in
                        HStack {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color(red: 0.90, green: 0.65, blue: 0.20))
                            Text(b).font(.custom("OpenSans-Regular", size: 13)).foregroundStyle(.primary)
                            Spacer()
                            Button { benefits.removeAll { $0 == b } } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 3

    private var step3View: some View {
        VStack(alignment: .leading, spacing: 20) {
            JobFormField(label: "How should candidates apply?") {
                VStack(spacing: 8) {
                    ForEach(ApplyModel.allCases) { model in
                        Button { applyModel = model } label: {
                            HStack(spacing: 12) {
                                Image(systemName: model.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(applyModel == model ? Color(red: 0.20, green: 0.55, blue: 0.95) : .secondary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.label).font(.custom("OpenSans-SemiBold", size: 14)).foregroundStyle(.primary)
                                    Text(applyModelDescription(model)).font(.custom("OpenSans-Regular", size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if applyModel == model {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
                                }
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(applyModel == model ? Color(red: 0.20, green: 0.55, blue: 0.95).opacity(0.4) : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if applyModel == .externalApply {
                JobFormField(label: "Application URL *") {
                    TextField("https://yourorg.com/apply", text: $externalURL)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            if let warning = safetyWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14)).foregroundStyle(Color(red: 0.90, green: 0.65, blue: 0.20))
                    Text(warning).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(.primary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.90, green: 0.65, blue: 0.20).opacity(0.10)))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Review")
                    .font(.custom("OpenSans-Bold", size: 16))
                jobReviewRow(icon: "briefcase.fill", label: "Title", value: title.isEmpty ? "(not set)" : title)
                jobReviewRow(icon: category.icon, label: "Category", value: category.label)
                jobReviewRow(icon: jobType.icon, label: "Type", value: jobType.label)
                jobReviewRow(icon: arrangement.icon, label: "Arrangement", value: arrangement.label)
                jobReviewRow(icon: classification.icon, label: "Organization", value: classification.label)
                jobReviewRow(icon: applyModel.icon, label: "Apply via", value: applyModel.label)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            if let err = errorMessage {
                Text(err).font(.custom("OpenSans-Regular", size: 12)).foregroundStyle(Color(red: 0.80, green: 0.35, blue: 0.35))
            }
        }
    }

    private func jobReviewRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.custom("OpenSans-Regular", size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.95))
            Text("Job Posted!")
                .font(.custom("OpenSans-Bold", size: 22))
            Text("Your opportunity is live. Qualified candidates will be able to discover and apply.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .font(.custom("OpenSans-Bold", size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(red: 0.20, green: 0.55, blue: 0.95), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(32)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step -= 1 } }
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                    .frame(width: 80, height: 48)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            Button {
                if step < 2 {
                    if step == 0 {
                        Task { await checkSafety() }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step += 1 }
                    }
                } else {
                    Task { await submitJob() }
                }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(step < 2 ? "Next" : "Post Job")
                            .font(.custom("OpenSans-Bold", size: 15))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(step1IsValid || step > 0 ? Color(red: 0.20, green: 0.55, blue: 0.95) : Color.secondary.opacity(0.3))
                )
            }
            .disabled((step == 0 && !step1IsValid) || isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var step1IsValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        description.trimmingCharacters(in: .whitespaces).count >= 20
    }

    // MARK: - Safety + Submit

    private func checkSafety() async {
        let mockListing = buildListing()
        let decision = await JobSafetyEngine.shared.evaluateJobPosting(mockListing)
        switch decision {
        case .warn(let msg):
            safetyWarning = msg
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step += 1 }
        case .allow:
            safetyWarning = nil
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step += 1 }
        case .block(let reason):
            errorMessage = reason
        default:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { step += 1 }
        }
    }

    private func submitJob() async {
        isSubmitting = true
        errorMessage = nil
        let listing = buildListing()
        do {
            try await service.postJob(listing)
            didPost = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    private func buildListing() -> JobListing {
        let userId = Auth.auth().currentUser?.uid ?? ""
        return JobListing(
            employerId: userId,
            employerName: service.myEmployerProfile?.organizationName ?? "My Organization",
            employerLogoURL: service.myEmployerProfile?.logoURL,
            employerVerified: service.myEmployerProfile?.isVerified ?? false,
            title: title,
            description: description,
            requirements: requirements,
            responsibilities: [],
            benefits: benefits,
            jobType: jobType,
            classification: classification,
            workArrangement: arrangement,
            category: category,
            skills: [],
            experienceLevel: experienceLevel,
            educationRequirement: nil,
            location: [city, state].filter { !$0.isEmpty }.joined(separator: ", "),
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            country: nil,
            compensationType: compensationType,
            salaryMin: Double(salaryMin),
            salaryMax: Double(salaryMax),
            salaryCurrency: "USD",
            salaryPeriod: salaryPeriod,
            applicationDeadline: nil,
            startDate: nil,
            applyModel: applyModel,
            externalApplyURL: applyModel == .externalApply ? externalURL : nil,
            screeningQuestions: [],
            isActive: true,
            isFeatured: postingTier == .featured,
            featuredExpiry: postingTier == .featured ? Calendar.current.date(byAdding: .day, value: 30, to: Date()) : nil,
            isPromoted: false,
            promotedExpiry: nil,
            postingTier: postingTier,
            moderationState: .active,
            safetyScore: 0.8,
            viewCount: 0,
            applicationCount: 0,
            saveCount: 0,
            searchKeywords: [],
            createdAt: Date(),
            updatedAt: Date(),
            expiresAt: Calendar.current.date(byAdding: .day, value: 60, to: Date())
        )
    }

    private func applyModelDescription(_ model: ApplyModel) -> String {
        switch model {
        case .externalApply:   return "Candidates click to apply on your website"
        case .amenEasyApply:   return "Candidates submit applications directly in AMEN"
        case .expressInterest: return "Candidates signal interest with a quick note"
        }
    }
}

// MARK: - Form Field Wrapper

struct JobFormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.primary)
            content
        }
    }
}
