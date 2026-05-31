//
//  ModernPrayerWallView.swift
//  AMENAPP
//
//  Created by Claude on 2/15/26.
//
//  Public prayer board with anonymous prayers, categories, and real-time updates
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Combine

struct ModernPrayerWallView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = PrayerWallViewModel()
    @State private var showNewPrayer = false
    @State private var selectedCategory: PrayerWallCategory = .all
    @State private var isRetrying = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prayer Wall")
                            .font(AMENFont.bold(32))
                            .foregroundStyle(.primary)

                        Text("Join believers around the world in prayer")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Category Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(PrayerWallCategory.allCases, id: \.self) { category in
                                PrayerCategoryPill(
                                    category: category,
                                    isSelected: selectedCategory == category
                                ) {
                                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                        selectedCategory = category
                                        viewModel.applyFilter(category)
                                    }
                                }
                                .accessibilityValue(selectedCategory == category ? "selected" : "not selected")
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Stats
                    HStack(spacing: 16) {
                        StatCard(
                            icon: "hands.sparkles.fill",
                            count: viewModel.totalPrayers,
                            label: "Prayers",
                            color: .blue
                        )
                        
                        StatCard(
                            icon: "person.2.fill",
                            count: viewModel.activePrayerWarriors,
                            label: "Praying",
                            color: .green
                        )
                        
                        StatCard(
                            icon: "checkmark.seal.fill",
                            count: viewModel.answeredToday,
                            label: "Answered",
                            color: .orange
                        )
                    }
                    .padding(.horizontal)
                    
                    // Error state
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(isRetrying ? "Retrying…" : "Retry") {
                                guard !isRetrying else { return }
                                isRetrying = true
                                Task {
                                    await viewModel.loadPrayers()
                                    isRetrying = false
                                }
                            }
                            .font(.subheadline.bold())
                            .disabled(isRetrying)
                        }
                        .padding()
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }

                    // Prayer Cards
                    if viewModel.isLoading && viewModel.prayers.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading prayers…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if viewModel.prayers.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("Be the first to share a prayer")
                                .font(AMENFont.bold(18))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)

                            Text("Your prayer community is here. Start by sharing what's on your heart.")
                                .font(AMENFont.regular(14))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 48)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.prayers) { prayer in
                                ModernPrayerCard(prayer: prayer) {
                                    await viewModel.prayForRequest(prayer)
                                }
                            }

                            if viewModel.hasMorePages {
                                Button {
                                    Task { await viewModel.loadMorePrayers() }
                                } label: {
                                    if viewModel.isLoadingMore {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        Text("Load more")
                                            .font(AMENFont.semiBold(15))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 12)
                                .disabled(viewModel.isLoadingMore)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                await viewModel.loadPrayers()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.systemScaled(16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewPrayer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.systemScaled(22))
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel("New prayer")
                    .accessibilityHint("Opens new prayer form")
                }
            }
            .sheet(isPresented: $showNewPrayer) {
                NewPrayerSheet { content, category, isAnonymous in
                    await viewModel.submitPrayer(
                        content: content,
                        category: category,
                        isAnonymous: isAnonymous
                    )
                }
            }
            .task {
                await viewModel.loadPrayers()
            }
            .amenAlert(
                isPresented: $viewModel.showActionError,
                config: LiquidGlassAlertConfig(
                    title: "Action Failed",
                    message: viewModel.actionErrorMessage,
                    primaryButton: LiquidGlassAlertButton("OK", tone: .primary, action: {
                        viewModel.actionErrorMessage = nil
                    })
                )
            )
        }
    }
    
}

// MARK: - Prayer Category Pill

private struct PrayerCategoryPill: View {
    let category: PrayerWallCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.systemScaled(12, weight: .semibold))
                Text(category.rawValue)
                    .font(AMENFont.semiBold(12))
            }
            .foregroundStyle(isSelected ? category.color : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(isSelected ? category.color.opacity(0.15) : Color.clear)
                    Capsule(style: .continuous)
                        .stroke(isSelected ? category.color.opacity(0.50) : Color.white.opacity(0.25), lineWidth: 0.6)
                }
            )
            .shadow(color: .black.opacity(isSelected ? 0.07 : 0.03), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(24, weight: .semibold))
                .foregroundStyle(color)
            
            Text("\(count)")
                .font(AMENFont.bold(20))
                .foregroundStyle(.primary)

            Text(label)
                .font(AMENFont.regular(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Modern Prayer Card

private struct ModernPrayerCard: View {
    let prayer: PrayerWallItem
    let onPray: () async -> Void
    
    @State private var isPraying = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                if prayer.isAnonymous {
                    Circle()
                        .fill(prayer.category.color.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.fill.questionmark")
                                .font(.systemScaled(16))
                                .foregroundStyle(prayer.category.color)
                        )
                        .accessibilityHidden(true)
                } else if let imageURL = prayer.authorProfileImage {
                    CachedAsyncImage(url: URL(string: imageURL)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(.tertiarySystemFill))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(prayer.isAnonymous ? "Anonymous" : prayer.authorName)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)

                    Text(prayer.timeAgo)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Category badge
                HStack(spacing: 4) {
                    Image(systemName: prayer.category.icon)
                        .font(.systemScaled(10, weight: .semibold))
                    Text(prayer.category.rawValue)
                        .font(AMENFont.semiBold(11))
                }
                .foregroundStyle(prayer.category.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(prayer.category.color.opacity(0.15))
                )
            }
            
            // Prayer content
            Text(prayer.content)
                .font(AMENFont.regular(15))
                .foregroundStyle(.primary)
                .lineSpacing(4)
            
            // Actions
            HStack(spacing: 20) {
                Button {
                    Task {
                        isPraying = true
                        await onPray()
                        isPraying = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isPraying ? "hands.sparkles.fill" : "hands.sparkles")
                            .font(.systemScaled(12, weight: .semibold))
                        Text("\(prayer.prayerCount)")
                            .font(AMENFont.semiBold(12))
                    }
                    .foregroundStyle(isPraying ? Color(red: 0.44, green: 0.26, blue: 0.80) : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            Capsule(style: .continuous).fill(.ultraThinMaterial)
                            Capsule(style: .continuous).fill(isPraying ? Color(red: 0.44, green: 0.26, blue: 0.80).opacity(0.12) : Color.clear)
                            Capsule(style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPraying)
                
                Spacer()
                
                if prayer.isAnswered {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.systemScaled(14))
                        Text("Answered!")
                            .font(AMENFont.semiBold(13))
                    }
                    .foregroundStyle(.green)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
}

// MARK: - New Prayer Sheet

private struct NewPrayerSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var supportDetectionService = SupportDetectionService.shared
    @ObservedObject private var supportActionExecutor = SupportActionExecutor.shared
    let onSubmit: (String, PrayerWallCategory, Bool) async -> Void
    
    @State private var content = ""
    @State private var selectedCategory: PrayerWallCategory = .requests
    @State private var isAnonymous = false
    @State private var isSubmitting = false
    @State private var supportDraftTask: Task<Void, Never>?
    @State private var supportDraftPayload: SupportInterventionPayload?
    @State private var showSupportDraftSheet = false
    @State private var bypassSupportGate = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .font(AMENFont.regular(15))
                        .accessibilityLabel("Prayer request")
                        .onChange(of: content) { _, newValue in
                            scheduleSupportDraftAnalysis(for: newValue)
                        }
                } header: {
                    Text("Your Prayer")
                }

                if let payload = supportDraftPayload {
                    Section {
                        switch payload.presentationMode {
                        case .chips(let chips):
                            SupportChipsRowView(
                                chips: chips,
                                onTap: handleSupportAction(_:),
                                onDismiss: dismissSupportPrompt
                            )
                        case .inlineCard(let model):
                            SupportInlineCardView(
                                model: model,
                                actions: payload.actions,
                                onTap: handleSupportAction(_:),
                                onDismiss: dismissSupportPrompt
                            )
                        case .none, .sheet:
                            EmptyView()
                        }
                    }
                }
                
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(PrayerWallCategory.allCases.filter { $0 != .all }, id: \.self) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    
                    Toggle("Post anonymously", isOn: $isAnonymous)
                }
            }
            .navigationTitle("Share Prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                            if shouldPresentSupportGate(for: trimmed) {
                                showSupportDraftSheet = true
                                return
                            }
                            isSubmitting = true
                            await onSubmit(content, selectedCategory, isAnonymous)
                            isSubmitting = false
                            dismiss()
                        }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
        .sheet(isPresented: $showSupportDraftSheet) {
            if let payload = supportDraftPayload,
               case .sheet(let model) = payload.presentationMode {
                SupportInterventionSheetView(
                    model: model,
                    actions: payload.actions,
                    onAction: handleSupportAction(_:),
                    onDismiss: dismissSupportPrompt,
                    onContinue: continueAfterSupportPrompt
                )
            }
        }
        .onDisappear {
            supportDraftTask?.cancel()
            supportDraftTask = nil
        }
        .supportDestinationSheet()
        .accessibilityIdentifier("screen.composer.prayer")
    }

    private func scheduleSupportDraftAnalysis(for text: String) {
        supportDraftTask?.cancel()
        bypassSupportGate = false

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            supportDraftPayload = nil
            return
        }

        supportDraftTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }

            let payload = await supportDetectionService.analyzeSupport(
                surface: .prayerRequest,
                text: trimmed,
                metadata: [
                    "category": selectedCategory.rawValue,
                    "isAnonymous": isAnonymous ? "true" : "false"
                ]
            )

            guard !Task.isCancelled else { return }
            await MainActor.run {
                supportDraftPayload = payload
                if let payload {
                    supportDetectionService.record(payload: payload, outcome: .shown)
                }
            }
        }
    }

    private func handleSupportAction(_ action: SupportAction) {
        guard let payload = supportDraftPayload else { return }
        supportActionExecutor.execute(action, from: .prayerRequest)
        supportDetectionService.record(payload: payload, outcome: .engaged)
        showSupportDraftSheet = false
    }

    private func dismissSupportPrompt() {
        if let payload = supportDraftPayload {
            supportDetectionService.record(payload: payload, outcome: .dismissed)
        }
        supportDraftPayload = nil
        showSupportDraftSheet = false
    }

    private func continueAfterSupportPrompt() {
        bypassSupportGate = true
        showSupportDraftSheet = false
    }

    private func shouldPresentSupportGate(for text: String) -> Bool {
        guard !bypassSupportGate,
              let payload = supportDraftPayload,
              payload.analyzedText == text,
              case .sheet = payload.presentationMode else {
            return false
        }

        return true
    }
}

// MARK: - Models

enum PrayerWallCategory: String, CaseIterable {
    case all = "All"
    case requests = "Requests"
    case praises = "Praises"
    case answered = "Answered"
    case healing = "Healing"
    case provision = "Provision"
    case guidance = "Guidance"
    
    var icon: String {
        switch self {
        case .all: return "globe.americas.fill"
        case .requests: return "hands.sparkles.fill"
        case .praises: return "hands.clap.fill"
        case .answered: return "checkmark.seal.fill"
        case .healing: return "cross.fill"
        case .provision: return "gift.fill"
        case .guidance: return "compass.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .all: return .gray
        case .requests: return .blue
        case .praises: return .orange
        case .answered: return .green
        case .healing: return .purple
        case .provision: return .pink
        case .guidance: return .teal
        }
    }
}

struct PrayerWallItem: Identifiable {
    let id: String
    let authorId: String
    let authorName: String
    let authorProfileImage: String?
    let content: String
    let category: PrayerWallCategory
    let timestamp: Date
    let isAnonymous: Bool
    var prayerCount: Int
    var isAnswered: Bool
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - ViewModel

@MainActor
class PrayerWallViewModel: ObservableObject {
    @Published var prayers: [PrayerWallItem] = []
    @Published var totalPrayers = 0
    @Published var activePrayerWarriors = 0
    @Published var answeredToday = 0
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var showActionError = false
    @Published var actionErrorMessage: String?

    @Published private(set) var hasMorePages = false
    private var lastDocument: DocumentSnapshot? = nil
    private var activeFilter: PrayerWallCategory = .all
    private let pageSize = 20

    private lazy var db = Firestore.firestore()

    // MARK: - Filter application

    func applyFilter(_ category: PrayerWallCategory) {
        prayers = []
        lastDocument = nil
        hasMorePages = false
        activeFilter = category
        Task { await loadPrayers() }
    }

    // MARK: - Query builder

    private func baseQuery() -> Query {
        var query: Query = db.collection(FirestoreCollections.prayerWall)
            .order(by: "timestamp", descending: true)

        if activeFilter != .all {
            query = query.whereField("category", isEqualTo: activeFilter.rawValue)
        }

        return query
    }

    // MARK: - Load first page

    func loadPrayers() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let snapshot = try await baseQuery()
                .limit(to: pageSize)
                .getDocuments()

            lastDocument = snapshot.documents.last
            hasMorePages = snapshot.documents.count == pageSize

            prayers = snapshot.documents.compactMap { Self.map(doc: $0) }

            totalPrayers = prayers.count
            activePrayerWarriors = Set(prayers.map { $0.authorId }).count
            answeredToday = prayers.filter { $0.isAnswered }.count

        } catch {
            errorMessage = "Unable to load prayers. Please try again."
            dlog("❌ Failed to load prayers: \(error)")
        }
    }

    // MARK: - Load next page

    func loadMorePrayers() async {
        guard let lastDoc = lastDocument, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let snapshot = try await baseQuery()
                .limit(to: pageSize)
                .start(afterDocument: lastDoc)
                .getDocuments()

            lastDocument = snapshot.documents.last
            hasMorePages = snapshot.documents.count == pageSize

            let newItems = snapshot.documents.compactMap { Self.map(doc: $0) }
            prayers.append(contentsOf: newItems)

            totalPrayers = prayers.count
            activePrayerWarriors = Set(prayers.map { $0.authorId }).count
            answeredToday = prayers.filter { $0.isAnswered }.count

        } catch {
            dlog("❌ Failed to load more prayers: \(error)")
        }
    }

    // MARK: - Document mapper

    private static func map(doc: QueryDocumentSnapshot) -> PrayerWallItem? {
        let data = doc.data()
        guard let categoryStr = data["category"] as? String,
              let category = PrayerWallCategory(rawValue: categoryStr) else {
            return nil
        }
        return PrayerWallItem(
            id: doc.documentID,
            authorId: data["authorId"] as? String ?? "",
            authorName: data["authorName"] as? String ?? "Unknown",
            authorProfileImage: data["authorProfileImage"] as? String,
            content: data["content"] as? String ?? "",
            category: category,
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? Date(),
            isAnonymous: data["isAnonymous"] as? Bool ?? false,
            prayerCount: data["prayerCount"] as? Int ?? 0,
            isAnswered: data["isAnswered"] as? Bool ?? false
        )
    }
    
    func submitPrayer(content: String, category: PrayerWallCategory, isAnonymous: Bool) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let userDoc = try await db.collection(FirestoreCollections.users).document(currentUserId).getDocument()
            let userData = userDoc.data()
            
            let prayerData: [String: Any] = [
                "authorId": currentUserId,
                "authorName": isAnonymous ? "Anonymous" : (userData?["username"] as? String ?? "Unknown"),
                "authorProfileImage": isAnonymous ? "" : (userData?["profileImageURL"] as? String ?? ""),
                "content": content,
                "category": category.rawValue,
                "timestamp": Timestamp(date: Date()),
                "isAnonymous": isAnonymous,
                "prayerCount": 0,
                "isAnswered": false
            ]
            
            try await db.collection(FirestoreCollections.prayerWall).addDocument(data: prayerData)
            await loadPrayers()

        } catch {
            dlog("❌ Failed to submit prayer: \(error)")
            actionErrorMessage = "Unable to share your prayer. Please try again."
            showActionError = true
        }
    }
    
    func prayForRequest(_ prayer: PrayerWallItem) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Check if already prayed
            let prayedDoc = try await db.collection(FirestoreCollections.prayerWall)
                .document(prayer.id)
                .collection(FirestoreCollections.prayers)
                .document(currentUserId)
                .getDocument()

            if !prayedDoc.exists {
                // Add prayer
                try await db.collection(FirestoreCollections.prayerWall)
                    .document(prayer.id)
                    .collection(FirestoreCollections.prayers)
                    .document(currentUserId)
                    .setData(["timestamp": Timestamp(date: Date())])

                // Increment count
                try await db.collection(FirestoreCollections.prayerWall)
                    .document(prayer.id)
                    .updateData(["prayerCount": FieldValue.increment(Int64(1))])
                
                // Update local
                if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
                    prayers[index].prayerCount += 1
                }
            }
        } catch {
            dlog("❌ Failed to pray: \(error)")
            actionErrorMessage = "Unable to record your prayer. Please try again."
            showActionError = true
        }
    }
}
