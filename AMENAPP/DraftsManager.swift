//
//  DraftsManager.swift
//  AMENAPP
//
//  Created by Steph on 1/21/26.
//

import SwiftUI
import Combine

// MARK: - Draft Model

struct PostDraft: Identifiable, Codable {
    let id: UUID
    let content: String
    let category: String
    let topicTag: String?
    let linkURL: String?
    let visibility: String
    let savedAt: Date
    
    var isExpired: Bool {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return savedAt < sevenDaysAgo
    }
    
    var daysRemaining: Int {
        let expiryDate = Calendar.current.date(byAdding: .day, value: 7, to: savedAt) ?? Date()
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day ?? 0
        return max(0, days)
    }
    
    var categoryIcon: String {
        switch category {
        case "#OPENTABLE":
            return "bubble.left.and.bubble.right.fill"
        case "Testimonies":
            return "star.bubble.fill"
        case "Prayer":
            return "hands.sparkles.fill"
        default:
            return "doc.text.fill"
        }
    }
    
    var categoryColor: Color {
        switch category {
        case "#OPENTABLE":
            return .orange
        case "Testimonies":
            return .yellow
        case "Prayer":
            return .blue
        default:
            return .gray
        }
    }
}

// MARK: - Drafts Manager

class DraftsManager: ObservableObject {
    @MainActor static let shared = DraftsManager()
    
    @Published var drafts: [PostDraft] = []
    
    private let draftsKey = "savedDrafts"
    
    private init() {
        loadDrafts()
        cleanupExpiredDrafts()
    }
    
    // MARK: - Load Drafts
    
    func loadDrafts() {
        guard let data = UserDefaults.standard.data(forKey: draftsKey),
              let decoded = try? JSONDecoder().decode([PostDraft].self, from: data) else {
            drafts = []
            return
        }
        
        // Filter out expired drafts
        drafts = decoded.filter { !$0.isExpired }
        saveDrafts() // Save filtered list
    }
    
    // MARK: - Save Draft
    
    func saveDraft(content: String, category: String, topicTag: String?, linkURL: String?, visibility: String) {
        let draft = PostDraft(
            id: UUID(),
            content: content,
            category: category,
            topicTag: topicTag,
            linkURL: linkURL,
            visibility: visibility,
            savedAt: Date()
        )
        
        drafts.insert(draft, at: 0)
        saveDrafts()
    }
    
    // MARK: - Delete Draft
    
    func deleteDraft(_ draft: PostDraft) {
        drafts.removeAll { $0.id == draft.id }
        saveDrafts()
    }
    
    // MARK: - Delete All Drafts
    
    func deleteAllDrafts() {
        drafts.removeAll()
        saveDrafts()
    }
    
    // MARK: - Cleanup Expired Drafts
    
    func cleanupExpiredDrafts() {
        let originalCount = drafts.count
        drafts.removeAll { $0.isExpired }
        
        if drafts.count != originalCount {
            saveDrafts()
            print("🗑️ Cleaned up \(originalCount - drafts.count) expired drafts")
        }
    }
    
    // MARK: - Private Methods
    
    private func saveDrafts() {
        if let encoded = try? JSONEncoder().encode(drafts) {
            UserDefaults.standard.set(encoded, forKey: draftsKey)
        }
    }
}
