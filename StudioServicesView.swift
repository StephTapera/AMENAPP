// StudioServicesView.swift
// AMEN Studio — Services Marketplace

import SwiftUI
import FirebaseAuth

// MARK: - Services List View (tab content inside StudioProfileView)

struct StudioServicesListView: View {
    let services: [StudioService_]
    let creatorId: String
    let isOwnProfile: Bool

    @State private var selectedService: StudioService_?
    @State private var showAddService = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if services.isEmpty {
                emptyServicesState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(services) { service in
                        StudioServiceCard(service: service)
                            .onTapGesture { selectedService = service }
                    }
                }
                .padding(.horizontal, 16)
            }

            if isOwnProfile {
                addServiceButton
            }
        }
        .padding(.top, 16)
        .sheet(item: $selectedService) { service in
            StudioServiceDetailView(service: service, creatorId: creatorId, isOwnProfile: isOwnProfile)
        }
        .sheet(isPresented: $showAddService) {
            StudioAddServiceView()
        }
    }

    @ViewBuilder
    private var emptyServicesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(isOwnProfile ? "List your services" : "No services listed")
                .font(.custom("OpenSans-SemiBold", size: 16))
            if isOwnProfile {
                Text("Offer design, media, consulting, or any creative service.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    @ViewBuilder
    private var addServiceButton: some View {
        Button {
            showAddService = true
        } label: {
            Label("Add a Service", systemImage: "plus.circle.fill")
                .font(.custom("OpenSans-SemiBold", size: 15))
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.liquidGlass)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Service Card

struct StudioServiceCard: View {
    let service: StudioService_

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(service.category.color.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: service.category.icon)
                    .font(.system(size: 22))
                    .foregroundStyle(service.category.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(service.title)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    servicePriceTag
                }

                Text(service.shortDescription)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    if let days = service.turnaroundDays {
                        serviceMetric(icon: "clock.fill", label: "\(days)d turnaround")
                    }
                    serviceMetric(icon: "arrow.triangle.2.circlepath", label: "\(service.revisionsIncluded) revision\(service.revisionsIncluded == 1 ? "" : "s")")
                    serviceMetric(icon: service.deliveryMethod.icon, label: service.deliveryMethod.label)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4).opacity(0.35), lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if service.isPromoted {
                Text("Promoted")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5), in: Capsule())
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var servicePriceTag: some View {
        Group {
            switch service.pricingType {
            case .free:
                Text("Free")
                    .font(.custom("OpenSans-Bold", size: 13))
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
            case .customQuote:
                Text("Custom Quote")
                    .font(.custom("OpenSans-Regular", size: 12))
                    .foregroundStyle(.secondary)
            case .fixed:
                if let price = service.startingPrice {
                    Text(price.formatted(.currency(code: service.currency)))
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                } else {
                    Text("Contact")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
            case .startingAt:
                if let price = service.startingPrice {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("From")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(price.formatted(.currency(code: service.currency)))
                            .font(.custom("OpenSans-Bold", size: 13))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func serviceMetric(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Service Detail View

struct StudioServiceDetailView: View {
    let service: StudioService_
    let creatorId: String
    let isOwnProfile: Bool

    @State private var showInquiry = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 10) {
                        StudioCategoryChip(category: service.category)
                        Text(service.title)
                            .font(.custom("OpenSans-Bold", size: 24))
                        pricingSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Divider().padding(.horizontal, 20)

                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("About This Service")
                        Text(service.fullDescription)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)

                    // Details grid
                    detailsGrid

                    // Transparency note
                    transparencyNote

                    // CTA
                    if !isOwnProfile && service.isAvailable {
                        inquiryCTA
                    }
                }
            }
            .navigationTitle("Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showInquiry) {
                StudioInquiryView(
                    creatorId: creatorId,
                    creatorName: "",
                    inquiryType: .service,
                    relatedItemId: service.id,
                    relatedItemTitle: service.title
                )
            }
        }
    }

    @ViewBuilder
    private var pricingSection: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            switch service.pricingType {
            case .free:
                Text("Free")
                    .font(.custom("OpenSans-Bold", size: 28))
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
            case .customQuote:
                VStack(alignment: .leading) {
                    Text("Custom Quote")
                        .font(.custom("OpenSans-Bold", size: 22))
                    Text("Submit an inquiry to receive a personalized quote.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            case .fixed:
                if let price = service.startingPrice {
                    Text(price.formatted(.currency(code: service.currency)))
                        .font(.custom("OpenSans-Bold", size: 28))
                }
            case .startingAt:
                if let price = service.startingPrice {
                    VStack(alignment: .leading) {
                        Text("Starting at")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(price.formatted(.currency(code: service.currency)))
                            .font(.custom("OpenSans-Bold", size: 28))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Details")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let days = service.turnaroundDays {
                    detailCell(icon: "clock.fill", label: "Turnaround", value: "\(days) days")
                }
                detailCell(icon: "arrow.triangle.2.circlepath", label: "Revisions", value: "\(service.revisionsIncluded) included")
                detailCell(icon: service.deliveryMethod.icon, label: "Delivery", value: service.deliveryMethod.label)
                if service.requiresDeposit {
                    detailCell(icon: "dollarsign.circle.fill", label: "Deposit", value: "\(service.depositPercent)% upfront")
                }
                if service.completionCount > 0 {
                    detailCell(icon: "checkmark.seal.fill", label: "Completed", value: "\(service.completionCount) projects")
                }
                if service.responseRatePercent > 0 {
                    detailCell(icon: "message.fill", label: "Response Rate", value: "\(service.responseRatePercent)%")
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var transparencyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("About AMEN Studio Transactions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("AMEN applies a small platform fee to support the service. You'll see the full breakdown before confirming.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var inquiryCTA: some View {
        VStack(spacing: 10) {
            Button {
                showInquiry = true
            } label: {
                Text("Send Inquiry")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.liquidGlass)

            if service.requiresDeposit {
                Text("\(service.depositPercent)% deposit required to begin")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private func detailCell(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("OpenSans-Bold", size: 16))
            .foregroundStyle(.primary)
    }
}

// MARK: - Add Service View

struct StudioAddServiceView: View {
    @StateObject private var studioService = StudioDataService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category: StudioCategory = .design
    @State private var shortDescription = ""
    @State private var fullDescription = ""
    @State private var pricingType: ServicePricingType = .startingAt
    @State private var startingPrice = ""
    @State private var turnaroundDays = ""
    @State private var revisionsIncluded = "2"
    @State private var deliveryMethod: DeliveryMethod = .digital
    @State private var isAvailable = true
    @State private var requiresDeposit = false
    @State private var depositPercent = "50"
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Service Info") {
                    TextField("Service Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(StudioCategory.allCases) { cat in
                            Label(cat.label, systemImage: cat.icon).tag(cat)
                        }
                    }
                    TextField("Short description (shown in listing)", text: $shortDescription)
                }

                Section("Full Description") {
                    TextEditor(text: $fullDescription)
                        .frame(minHeight: 100)
                }

                Section("Pricing") {
                    Picker("Pricing Type", selection: $pricingType) {
                        ForEach(ServicePricingType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    if pricingType != .free && pricingType != .customQuote {
                        TextField("Starting Price (USD)", text: $startingPrice)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Delivery") {
                    Picker("Delivery Method", selection: $deliveryMethod) {
                        ForEach(DeliveryMethod.allCases, id: \.self) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    TextField("Turnaround (days)", text: $turnaroundDays)
                        .keyboardType(.numberPad)
                    TextField("Revisions included", text: $revisionsIncluded)
                        .keyboardType(.numberPad)
                }

                Section("Options") {
                    Toggle("Currently available", isOn: $isAvailable)
                    Toggle("Requires deposit", isOn: $requiresDeposit)
                    if requiresDeposit {
                        TextField("Deposit percent (e.g. 50)", text: $depositPercent)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle("Add Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveService() }
                        .disabled(title.isEmpty || isSaving)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
        }
    }

    private func saveService() {
        guard let userId = studioService.myProfile?.userId ?? Auth.auth().currentUser?.uid else { return }
        isSaving = true
        let service = StudioService_(
            creatorId: userId,
            title: title,
            category: category,
            shortDescription: shortDescription,
            fullDescription: fullDescription,
            pricingType: pricingType,
            startingPrice: Double(startingPrice),
            currency: "USD",
            turnaroundDays: Int(turnaroundDays),
            revisionsIncluded: Int(revisionsIncluded) ?? 2,
            deliveryMethod: deliveryMethod,
            sampleWorkIds: [],
            isAvailable: isAvailable,
            requiresDeposit: requiresDeposit,
            depositPercent: Int(depositPercent) ?? 50,
            moderationState: .active,
            inquiryCount: 0,
            completionCount: 0,
            responseRatePercent: 100,
            createdAt: Date(),
            updatedAt: Date(),
            searchKeywords: [title.lowercased(), category.rawValue],
            isPromoted: false
        )
        Task {
            try? await studioService.saveService(service)
            isSaving = false
            dismiss()
        }
    }
}

// MARK: - Studio Edit Profile View (stub)

struct StudioEditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = StudioDataService.shared

    @State private var displayName = ""
    @State private var tagline = ""
    @State private var bio = ""
    @State private var isOpenForWork = true
    @State private var isOpenForCommissions = false
    @State private var inquiryPolicy: InquiryPolicy = .everyone
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display Name", text: $displayName)
                    TextField("Tagline — what do you do?", text: $tagline)
                }
                Section("Bio") {
                    TextEditor(text: $bio).frame(minHeight: 80)
                }
                Section("Availability") {
                    Toggle("Open for Work", isOn: $isOpenForWork)
                    Toggle("Open for Commissions", isOn: $isOpenForCommissions)
                    Picker("Who can inquire?", selection: $inquiryPolicy) {
                        ForEach([InquiryPolicy.everyone, .followersOnly, .approvedOnly, .closed], id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                }
            }
            .navigationTitle("Edit Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            .onAppear {
                if let profile = service.myProfile {
                    displayName = profile.displayName
                    tagline = profile.tagline
                    bio = profile.bio
                    isOpenForWork = profile.isOpenForWork
                    isOpenForCommissions = profile.isOpenForCommissions
                    inquiryPolicy = profile.inquiryPolicy
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            if var profile = service.myProfile {
                profile.displayName = displayName
                profile.tagline = tagline
                profile.bio = bio
                profile.isOpenForWork = isOpenForWork
                profile.isOpenForCommissions = isOpenForCommissions
                profile.inquiryPolicy = inquiryPolicy
                try? await service.saveProfile(profile)
            }
            isSaving = false
            dismiss()
        }
    }
}
