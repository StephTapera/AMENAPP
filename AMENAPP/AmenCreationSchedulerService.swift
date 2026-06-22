// AmenCreationSchedulerService.swift
// AMENAPP
// Handles scheduling posts for future publication via Firestore.
// The backend reads scheduledPosts collection via a scheduled Cloud Function.

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - Scheduled Post Model

struct ScheduledPost: Identifiable, Codable {
    var id: String
    var userId: String
    var text: String
    var mediaURLs: [String]
    var intent: AmenCreationIntent
    var hashtags: [String]
    var scheduledAt: Date
    var status: AmenScheduledPostStatus
    var createdAt: Date
    var updatedAt: Date
    var failureReason: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, text, mediaURLs, intent, hashtags
        case scheduledAt, status, createdAt, updatedAt, failureReason
    }

    init(
        id: String,
        userId: String,
        text: String,
        mediaURLs: [String],
        intent: AmenCreationIntent,
        hashtags: [String],
        scheduledAt: Date,
        status: AmenScheduledPostStatus,
        createdAt: Date,
        updatedAt: Date,
        failureReason: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.text = text
        self.mediaURLs = mediaURLs
        self.intent = intent
        self.hashtags = hashtags
        self.scheduledAt = scheduledAt
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.failureReason = failureReason
    }

    init?(id: String, data: [String: Any]) {
        guard
            let userId = data["userId"] as? String,
            let text = data["text"] as? String,
            let intentRaw = data["intent"] as? String,
            let intent = AmenCreationIntent(rawValue: intentRaw),
            let scheduledTs = data["scheduledAt"] as? Timestamp,
            let statusRaw = data["status"] as? String,
            let status = AmenScheduledPostStatus(rawValue: statusRaw),
            let createdTs = data["createdAt"] as? Timestamp,
            let updatedTs = data["updatedAt"] as? Timestamp
        else { return nil }

        self.id = id
        self.userId = userId
        self.text = text
        self.mediaURLs = data["mediaURLs"] as? [String] ?? []
        self.intent = intent
        self.hashtags = data["hashtags"] as? [String] ?? []
        self.scheduledAt = scheduledTs.dateValue()
        self.status = status
        self.createdAt = createdTs.dateValue()
        self.updatedAt = updatedTs.dateValue()
        self.failureReason = data["failureReason"] as? String
    }

    var firestoreData: [String: Any] {
        [
            "userId": userId,
            "text": text,
            "mediaURLs": mediaURLs,
            "intent": intent.rawValue,
            "hashtags": hashtags,
            "scheduledAt": Timestamp(date: scheduledAt),
            "status": status.rawValue,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "failureReason": failureReason as Any
        ]
    }
}

enum AmenScheduledPostStatus: String, Codable {
    case pending
    case published
    case failed
    case cancelled
}

// MARK: - Service

@MainActor
final class AmenCreationSchedulerService: ObservableObject {
    static let shared = AmenCreationSchedulerService()

    @Published private(set) var scheduledPosts: [ScheduledPost] = []
    @Published private(set) var isLoading = false

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startObserving() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listener?.remove()
        listener = db.collection("users").document(uid)
            .collection("scheduledPosts")
            .whereField("status", isEqualTo: AmenScheduledPostStatus.pending.rawValue)
            .order(by: "scheduledAt")
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let docs = snap?.documents else { return }
                self.scheduledPosts = docs.compactMap { ScheduledPost(id: $0.documentID, data: $0.data()) }
            }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
    }

    // MARK: - Schedule a new post

    func schedulePost(
        text: String,
        mediaURLs: [String] = [],
        intent: AmenCreationIntent,
        hashtags: [String] = [],
        at date: Date
    ) async throws -> ScheduledPost {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SchedulerError.notAuthenticated
        }
        guard date > Date() else {
            throw SchedulerError.scheduledDateInPast
        }

        let now = Date()
        let ref = db.collection("users").document(uid)
            .collection("scheduledPosts").document()

        let post = ScheduledPost(
            id: ref.documentID,
            userId: uid,
            text: text,
            mediaURLs: mediaURLs,
            intent: intent,
            hashtags: hashtags,
            scheduledAt: date,
            status: .pending,
            createdAt: now,
            updatedAt: now
        )

        try await ref.setData(post.firestoreData)
        return post
    }

    // MARK: - Cancel

    func cancelPost(_ post: ScheduledPost) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let id = post.id
        try await db.collection("users").document(uid)
            .collection("scheduledPosts").document(id)
            .updateData(["status": AmenScheduledPostStatus.cancelled.rawValue])
    }

    // MARK: - Reschedule

    func reschedulePost(_ post: ScheduledPost, to newDate: Date) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let id = post.id
        guard newDate > Date() else { throw SchedulerError.scheduledDateInPast }
        try await db.collection("users").document(uid)
            .collection("scheduledPosts").document(id)
            .updateData([
                "scheduledAt": Timestamp(date: newDate),
                "updatedAt": Timestamp(date: Date())
            ])
    }

    enum SchedulerError: LocalizedError {
        case notAuthenticated
        case scheduledDateInPast

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "You must be signed in to schedule posts."
            case .scheduledDateInPast: return "Scheduled time must be in the future."
            }
        }
    }
}

// MARK: - Schedule Composer Sheet

struct AmenSchedulePostSheet: View {
    let draft: AmenCreationDraft
    var onScheduled: ((Date) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scheduler = AmenCreationSchedulerService.shared
    @State private var selectedDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var isScheduling = false
    @State private var errorMessage: String? = nil

    private var isValidDate: Bool { selectedDate > Date() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Publish at",
                        selection: $selectedDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("Your post will be published automatically at the selected time. You can cancel it before then.")
                        .font(.caption)
                }

                Section("Post Preview") {
                    Text(draft.text.isEmpty ? "(empty post)" : draft.text)
                        .font(.body)
                        .foregroundStyle(draft.text.isEmpty ? .secondary : .primary)
                        .lineLimit(4)

                    let inferredHashtags = extractHashtags(from: draft.text)
                    if !inferredHashtags.isEmpty {
                        Text(inferredHashtags.joined(separator: " "))
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Schedule Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await schedule() }
                    } label: {
                        if isScheduling {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Text("Schedule").fontWeight(.semibold)
                        }
                    }
                    .disabled(!isValidDate || isScheduling)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func schedule() async {
        isScheduling = true
        errorMessage = nil
        do {
            _ = try await scheduler.schedulePost(
                text: draft.text,
                mediaURLs: [],
                intent: draft.intent,
                hashtags: extractHashtags(from: draft.text),
                at: selectedDate
            )
            onScheduled?(selectedDate)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isScheduling = false
    }

    private func extractHashtags(from text: String) -> [String] {
        let pattern = "#[A-Za-z0-9_]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, range: range)
        let tags = matches.map { ns.substring(with: $0.range) }
        return Array(Set(tags)).sorted()
    }
}

// MARK: - Scheduled Posts Manager View

struct AmenScheduledPostsView: View {
    @StateObject private var scheduler = AmenCreationSchedulerService.shared
    @State private var postToReschedule: ScheduledPost? = nil
    @State private var newRescheduleDate = Date()

    var body: some View {
        List {
            if scheduler.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if scheduler.scheduledPosts.isEmpty {
                ContentUnavailableView(
                    "No Scheduled Posts",
                    systemImage: "calendar.badge.clock",
                    description: Text("Posts you schedule will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(scheduler.scheduledPosts) { post in
                    scheduledPostRow(post)
                }
            }
        }
        .navigationTitle("Scheduled Posts")
        .navigationBarTitleDisplayMode(.inline)
        .task { scheduler.startObserving() }
        .onDisappear { scheduler.stopObserving() }
        .sheet(item: $postToReschedule) { post in
            reschedulePicker(post: post)
        }
    }

    private func scheduledPostRow(_ post: ScheduledPost) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.text.isEmpty ? "(no text)" : post.text)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 8) {
                Label(
                    post.scheduledAt.formatted(.dateTime.month().day().hour().minute()),
                    systemImage: "calendar.clock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text(post.intent.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                newRescheduleDate = post.scheduledAt
                postToReschedule = post
            } label: {
                Label("Reschedule", systemImage: "calendar.badge.plus")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { try? await scheduler.cancelPost(post) }
            } label: {
                Label("Cancel", systemImage: "trash")
            }
        }
    }

    private func reschedulePicker(post: ScheduledPost) -> some View {
        NavigationStack {
            Form {
                DatePicker(
                    "New publish time",
                    selection: $newRescheduleDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle("Reschedule Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { postToReschedule = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task {
                            try? await scheduler.reschedulePost(post, to: newRescheduleDate)
                            postToReschedule = nil
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(newRescheduleDate <= Date())
                }
            }
        }
        .presentationDetents([.medium])
    }
}
