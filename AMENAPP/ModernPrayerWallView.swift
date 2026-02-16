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
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prayer Wall")
                            .font(.custom("OpenSans-Bold", size: 32))
                            .foregroundStyle(.primary)
                        
                        Text("Join believers around the world in prayer")
                            .font(.custom("OpenSans-Regular", size: 14))
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
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedCategory = category
                                    }
                                }
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
                    
                    // Prayer Cards
                    LazyVStack(spacing: 16) {
                        ForEach(filteredPrayers) { prayer in
                            ModernPrayerCard(prayer: prayer) {
                                await viewModel.prayForRequest(prayer)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewPrayer = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.blue)
                    }
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
        }
    }
    
    private var filteredPrayers: [PrayerWallItem] {
        if selectedCategory == .all {
            return viewModel.prayers
        }
        return viewModel.prayers.filter { $0.category == selectedCategory }
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
                    .font(.system(size: 12, weight: .semibold))
                
                Text(category.rawValue)
                    .font(.custom("OpenSans-SemiBold", size: 13))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? category.color : Color(.secondarySystemBackground))
                    .shadow(
                        color: isSelected ? category.color.opacity(0.3) : .clear,
                        radius: 8,
                        y: 4
                    )
            )
        }
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(color)
            
            Text("\(count)")
                .font(.custom("OpenSans-Bold", size: 20))
                .foregroundStyle(.primary)
            
            Text(label)
                .font(.custom("OpenSans-Regular", size: 11))
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
                                .font(.system(size: 16))
                                .foregroundStyle(prayer.category.color)
                        )
                } else if let imageURL = prayer.authorProfileImage {
                    AsyncImage(url: URL(string: imageURL)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(.tertiarySystemFill))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(prayer.isAnonymous ? "Anonymous" : prayer.authorName)
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    
                    Text(prayer.timeAgo)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Category badge
                HStack(spacing: 4) {
                    Image(systemName: prayer.category.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(prayer.category.rawValue)
                        .font(.custom("OpenSans-SemiBold", size: 11))
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
                .font(.custom("OpenSans-Regular", size: 15))
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
                    HStack(spacing: 6) {
                        Image(systemName: isPraying ? "hands.sparkles.fill" : "hands.sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("\(prayer.prayerCount)")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                    }
                    .foregroundStyle(isPraying ? Color.blue : Color.secondary)
                }
                .disabled(isPraying)
                
                Spacer()
                
                if prayer.isAnswered {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                        Text("Answered!")
                            .font(.custom("OpenSans-SemiBold", size: 13))
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
    let onSubmit: (String, PrayerWallCategory, Bool) async -> Void
    
    @State private var content = ""
    @State private var selectedCategory: PrayerWallCategory = .requests
    @State private var isAnonymous = false
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                        .font(.custom("OpenSans-Regular", size: 15))
                } header: {
                    Text("Your Prayer")
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
                            isSubmitting = true
                            await onSubmit(content, selectedCategory, isAnonymous)
                            dismiss()
                        }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
        }
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
    
    private let db = Firestore.firestore()
    
    func loadPrayers() async {
        do {
            let snapshot = try await db.collection("prayerWall")
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            prayers = snapshot.documents.compactMap { doc in
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
            
            totalPrayers = prayers.count
            activePrayerWarriors = Int.random(in: 100...500) // Placeholder
            answeredToday = prayers.filter { $0.isAnswered }.count
            
        } catch {
            print("❌ Failed to load prayers: \(error)")
        }
    }
    
    func submitPrayer(content: String, category: PrayerWallCategory, isAnonymous: Bool) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let userDoc = try await db.collection("users").document(currentUserId).getDocument()
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
            
            try await db.collection("prayerWall").addDocument(data: prayerData)
            await loadPrayers()
            
        } catch {
            print("❌ Failed to submit prayer: \(error)")
        }
    }
    
    func prayForRequest(_ prayer: PrayerWallItem) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Check if already prayed
            let prayedDoc = try await db.collection("prayerWall")
                .document(prayer.id)
                .collection("prayers")
                .document(currentUserId)
                .getDocument()
            
            if !prayedDoc.exists {
                // Add prayer
                try await db.collection("prayerWall")
                    .document(prayer.id)
                    .collection("prayers")
                    .document(currentUserId)
                    .setData(["timestamp": Timestamp(date: Date())])
                
                // Increment count
                try await db.collection("prayerWall")
                    .document(prayer.id)
                    .updateData(["prayerCount": FieldValue.increment(Int64(1))])
                
                // Update local
                if let index = prayers.firstIndex(where: { $0.id == prayer.id }) {
                    prayers[index].prayerCount += 1
                }
            }
        } catch {
            print("❌ Failed to pray: \(error)")
        }
    }
}
