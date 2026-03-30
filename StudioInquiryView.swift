// StudioInquiryView.swift
// AMEN Studio — Inquiry, Booking, and Support Forms

import SwiftUI

// MARK: - Studio Inquiry View (Service / General Inquiry)

struct StudioInquiryView: View {
    let creatorId: String
    let creatorName: String
    let inquiryType: InquiryType
    var relatedItemId: String? = nil
    var relatedItemTitle: String? = nil

    @StateObject private var service = StudioDataService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var message = ""
    @State private var budget = ""
    @State private var timeline = ""
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            if submitted {
                inquirySubmittedState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Context header
                        contextHeader

                        VStack(alignment: .leading, spacing: 16) {
                            // Subject
                            formField(label: "Subject") {
                                TextField(subjectPlaceholder, text: $subject)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            }

                            // Message
                            formField(label: "Message") {
                                ZStack(alignment: .topLeading) {
                                    if message.isEmpty {
                                        Text(messagePlaceholder)
                                            .font(.system(size: 15))
                                            .foregroundStyle(.tertiary)
                                            .padding(12)
                                    }
                                    TextEditor(text: $message)
                                        .frame(minHeight: 120)
                                        .padding(8)
                                }
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            }

                            // Budget (optional)
                            formField(label: "Budget (optional)") {
                                HStack {
                                    Text("$")
                                        .foregroundStyle(.secondary)
                                    TextField("e.g. 500", text: $budget)
                                        .keyboardType(.decimalPad)
                                }
                                .padding(12)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            }

                            // Timeline (optional)
                            formField(label: "Timeline (optional)") {
                                TextField("e.g. Need this by March 2026", text: $timeline)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 20)

                        safetyDisclosure
                        submitButton
                    }
                    .padding(.bottom, 40)
                }
                .navigationTitle(inquiryType.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                }
            }
        }
    }

    // MARK: - Context Header

    @ViewBuilder
    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !creatorName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("To: \(creatorName)")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                }
            }
            if let title = relatedItemTitle {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Re: \(title)")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    @ViewBuilder
    private var safetyDisclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
                Text("Safe & Moderated")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
            }
            Text("Your message is reviewed for safety. Never share payment info, personal data, or off-platform links in an initial inquiry.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(red: 0.18, green: 0.62, blue: 0.36).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var submitButton: some View {
        Button {
            submitInquiry()
        } label: {
            HStack {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Send Inquiry")
                        .font(.custom("OpenSans-Bold", size: 16))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.liquidGlass)
        .disabled(subject.isEmpty || message.isEmpty || isSubmitting)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var inquirySubmittedState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))

            Text("Inquiry Sent")
                .font(.custom("OpenSans-Bold", size: 24))

            Text("Your inquiry has been delivered to \(creatorName.isEmpty ? "the creator" : creatorName). They'll respond through your messages.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color(red: 0.15, green: 0.45, blue: 0.90), in: RoundedRectangle(cornerRadius: 14))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.custom("OpenSans-SemiBold", size: 13))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var subjectPlaceholder: String {
        switch inquiryType {
        case .service:       return "What service are you interested in?"
        case .commission:    return "Tell me about your project"
        case .booking:       return "What are you looking to book?"
        case .collaboration: return "Let's work together on..."
        case .general:       return "What's on your mind?"
        case .opportunity:   return "Opportunity: "
        }
    }

    private var messagePlaceholder: String {
        "Share details about your needs, goals, and any relevant context..."
    }

    private func submitInquiry() {
        isSubmitting = true
        Task {
            try? await service.sendInquiry(
                toCreatorId: creatorId,
                subject: subject,
                message: message,
                type: inquiryType,
                relatedItemId: relatedItemId
            )
            isSubmitting = false
            submitted = true
        }
    }
}

// MARK: - Studio Booking View

struct StudioBookingView: View {
    let creatorId: String
    let creatorName: String

    @StateObject private var service = StudioDataService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var bookingType: BookingType = .speaking
    @State private var title = ""
    @State private var description = ""
    @State private var hasEventDate = false
    @State private var eventDate = Date().addingTimeInterval(60 * 60 * 24 * 14)
    @State private var durationHours = "1"
    @State private var location = ""
    @State private var isVirtual = false
    @State private var budget = ""
    @State private var expectations = ""
    @State private var isSubmitting = false
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            if submitted {
                bookingSubmittedState
            } else {
                Form {
                    Section("Booking Type") {
                        Picker("Type", selection: $bookingType) {
                            ForEach(BookingType.allCases, id: \.self) { type in
                                Label(type.label, systemImage: type.icon).tag(type)
                            }
                        }
                        TextField("Event Title", text: $title)
                    }

                    Section("Details") {
                        TextEditor(text: $description)
                            .frame(minHeight: 80)
                            .overlay(alignment: .topLeading) {
                                if description.isEmpty {
                                    Text("Describe the event, audience, and what you need...")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.tertiary)
                                        .padding(5)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    Section("Date & Location") {
                        Toggle("I have a specific date", isOn: $hasEventDate)
                        if hasEventDate {
                            DatePicker("Event Date", selection: $eventDate)
                            TextField("Duration (hours)", text: $durationHours).keyboardType(.decimalPad)
                        }
                        Toggle("Virtual / Remote", isOn: $isVirtual)
                        if !isVirtual {
                            TextField("Location / City", text: $location)
                        }
                    }

                    Section("Budget & Expectations") {
                        TextField("Budget (optional, USD)", text: $budget).keyboardType(.decimalPad)
                        TextEditor(text: $expectations)
                            .frame(minHeight: 60)
                            .overlay(alignment: .topLeading) {
                                if expectations.isEmpty {
                                    Text("What outcome are you hoping for?")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.tertiary)
                                        .padding(5)
                                        .allowsHitTesting(false)
                                }
                            }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No commitment required")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Submitting this request doesn't create a contract. The creator will review your request and respond to confirm or discuss details.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Booking Request")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Send") { submit() }
                            .disabled(title.isEmpty || isSubmitting)
                            .font(.custom("OpenSans-SemiBold", size: 15))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bookingSubmittedState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 56))
                .foregroundStyle(Color(red: 0.18, green: 0.62, blue: 0.36))
            Text("Booking Request Sent")
                .font(.custom("OpenSans-Bold", size: 22))
            Text("Your booking request has been sent to \(creatorName). They'll respond through your messages.")
                .font(.custom("OpenSans-Regular", size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Done") { dismiss() }
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 14)
                .background(Color(red: 0.18, green: 0.62, blue: 0.36), in: RoundedRectangle(cornerRadius: 14))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        guard let userId = service.myProfile?.userId else { return }
        isSubmitting = true
        let request = StudioBookingRequest(
            creatorId: creatorId,
            requesterId: userId,
            requesterName: service.myProfile?.displayName ?? "Anonymous",
            bookingType: bookingType,
            title: title,
            description: description,
            eventDate: hasEventDate ? eventDate : nil,
            eventDurationHours: Double(durationHours),
            location: isVirtual ? nil : location,
            isVirtual: isVirtual,
            budget: Double(budget),
            expectations: expectations,
            status: .pending,
            moderationFlag: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        Task {
            try? await service.submitBookingRequest(request)
            isSubmitting = false
            submitted = true
        }
    }
}

// MARK: - Studio Inbox View (Creator's incoming inquiries)

struct StudioInboxView: View {
    @StateObject private var service = StudioDataService.shared
    @State private var threads: [StudioInquiryThread] = []
    @State private var isLoading = true
    @State private var selectedThread: StudioInquiryThread?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if threads.isEmpty {
                    emptyInboxState
                } else {
                    List(threads) { thread in
                        StudioInboxRow(thread: thread)
                            .onTapGesture { selectedThread = thread }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Studio Inbox")
            .navigationBarTitleDisplayMode(.large)
            .task {
                threads = await service.fetchMyInquiryThreads()
                isLoading = false
            }
        }
    }

    @ViewBuilder
    private var emptyInboxState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No inquiries yet")
                .font(.custom("OpenSans-SemiBold", size: 18))
            Text("When someone sends you an inquiry or booking request, it will appear here.")
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StudioInboxRow: View {
    let thread: StudioInquiryThread

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.15, green: 0.45, blue: 0.90).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: thread.threadType == .booking ? "calendar.fill" : "envelope.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.15, green: 0.45, blue: 0.90))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(thread.inquirerName)
                        .font(.custom("OpenSans-SemiBold", size: 14))
                    Spacer()
                    Text(thread.lastMessageAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(thread.subject)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(thread.lastMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !thread.isReadByCreator {
                Circle()
                    .fill(Color(red: 0.15, green: 0.45, blue: 0.90))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
    }
}
