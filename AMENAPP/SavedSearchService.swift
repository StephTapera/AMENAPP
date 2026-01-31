//
//  SavedSearchService.swift
//  AMENAPP
//
//  Created by Steph on 1/30/26.
//
//  Service for managing saved searches and search notifications
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Saved Search Model

public struct SavedSearch: Identifiable, Codable {
    @DocumentID public var id: String?
    var userId: String
    var query: String
    var category: String?           // Optional: "Prayer", "Testimony", "Users", etc.
    var filters: [String]           // Simplified to array of strings
    var notificationsEnabled: Bool
    var createdAt: Date
    var lastTriggered: Date?        // Last time check was triggered
    var triggerCount: Int           // Number of times checked
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case query
        case category
        case filters
        case notificationsEnabled
        case createdAt
        case lastTriggered
        case triggerCount
    }
    
    init(
        id: String? = nil,
        userId: String,
        query: String,
        category: String? = nil,
        filters: [String] = [],
        notificationsEnabled: Bool = true,
        createdAt: Date = Date(),
        lastTriggered: Date? = nil,
        triggerCount: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.query = query
        self.category = category
        self.filters = filters
        self.notificationsEnabled = notificationsEnabled
        self.createdAt = createdAt
        self.lastTriggered = lastTriggered
        self.triggerCount = triggerCount
    }
}

// MARK: - Search Alert Model

public struct SearchAlert: Identifiable, Codable {
    @DocumentID public var id: String?
    var userId: String
    var savedSearchId: String
    var query: String
    var resultCount: Int
    var isRead: Bool
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case savedSearchId
        case query
        case resultCount
        case isRead
        case createdAt
    }
    
    init(
        id: String? = nil,
        userId: String,
        savedSearchId: String,
        query: String,
        resultCount: Int,
        isRead: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.savedSearchId = savedSearchId
        self.query = query
        self.resultCount = resultCount
        self.isRead = isRead
        self.createdAt = createdAt
    }
}

// MARK: - Saved Search Service

@MainActor
class SavedSearchService: ObservableObject {
    static let shared = SavedSearchService()
    
    @Published var savedSearches: [SavedSearch] = []
    @Published var searchAlerts: [SearchAlert] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var alertsListener: ListenerRegistration?
    
    private init() {}
    
    // MARK: - Save Search
    
    /// Save a search query for notifications
    func saveSearch(
        query: String,
        category: String? = nil,
        filters: [String] = [],
        notificationsEnabled: Bool = true
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        // Check if query is already saved
        let existingSearches = try await fetchSavedSearches()
        if existingSearches.contains(where: { $0.query.lowercased() == query.lowercased() && $0.category == category }) {
            print("⚠️ Search already saved: \(query)")
            throw SavedSearchError.alreadySaved
        }
        
        let savedSearch = SavedSearch(
            userId: userId,
            query: query,
            category: category,
            filters: filters,
            notificationsEnabled: notificationsEnabled
        )
        
        // Convert to dictionary for Firestore
        var data: [String: Any] = [
            "userId": savedSearch.userId,
            "query": savedSearch.query,
            "notificationsEnabled": savedSearch.notificationsEnabled,
            "createdAt": savedSearch.createdAt,
            "triggerCount": savedSearch.triggerCount,
            "filters": savedSearch.filters
        ]
        
        if let category = savedSearch.category {
            data["category"] = category
        }
        
        try await db.collection("savedSearches").addDocument(data: data)
        
        print("✅ Search saved: \(query)")
        
        // Trigger haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    // MARK: - Fetch Saved Searches
    
    /// Fetch all saved searches for current user
    func fetchSavedSearches() async throws -> [SavedSearch] {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let snapshot = try await db.collection("savedSearches")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let searches = snapshot.documents.compactMap { doc -> SavedSearch? in
            var search = try? doc.data(as: SavedSearch.self)
            search?.id = doc.documentID
            return search
        }
        
        savedSearches = searches
        
        print("✅ Fetched \(searches.count) saved searches")
        
        return searches
    }
    
    // MARK: - Delete Saved Search
    
    /// Delete a saved search
    func deleteSavedSearch(id: String) async throws {
        try await db.collection("savedSearches").document(id).delete()
        
        // Remove from local cache
        savedSearches.removeAll { $0.id == id }
        
        print("✅ Deleted saved search: \(id)")
        
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
    }
    
    // MARK: - Toggle Notifications
    
    /// Enable/disable notifications for a saved search
    func toggleNotifications(searchId: String) async throws {
        guard let index = savedSearches.firstIndex(where: { $0.id == searchId }) else {
            return
        }
        
        let newValue = !savedSearches[index].notificationsEnabled
        
        try await db.collection("savedSearches").document(searchId).updateData([
            "notificationsEnabled": newValue
        ])
        
        // Update local cache
        savedSearches[index].notificationsEnabled = newValue
        
        print("✅ Notifications \(newValue ? "enabled" : "disabled") for search: \(searchId)")
    }
    
    // MARK: - Check for New Results
    
    /// Manually trigger a check for new results for a saved search
    func checkForNewResults(savedSearch: SavedSearch) async {
        guard let searchId = savedSearch.id else { return }
        
        // Update trigger count and last triggered date
        do {
            try await db.collection("savedSearches").document(searchId).updateData([
                "triggerCount": FieldValue.increment(Int64(1)),
                "lastTriggered": Date()
            ])
            
            // Update local cache
            if let index = savedSearches.firstIndex(where: { $0.id == searchId }) {
                savedSearches[index].triggerCount += 1
                savedSearches[index].lastTriggered = Date()
            }
            
            print("✅ Triggered check for search: \(savedSearch.query)")
            
            // In a real implementation, you would perform the actual search here
            // and create alerts if new results are found
            
        } catch {
            print("❌ Failed to trigger search check: \(error)")
        }
    }
    
    // MARK: - Search Alerts
    
    /// Fetch alerts for the current user
    func fetchAlerts() async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let snapshot = try await db.collection("searchAlerts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        
        let alerts = snapshot.documents.compactMap { doc -> SearchAlert? in
            var alert = try? doc.data(as: SearchAlert.self)
            alert?.id = doc.documentID
            return alert
        }
        
        searchAlerts = alerts
        
        print("✅ Fetched \(alerts.count) search alerts")
    }
    
    /// Mark an alert as read
    func markAlertAsRead(alertId: String) async throws {
        try await db.collection("searchAlerts").document(alertId).updateData([
            "isRead": true
        ])
        
        // Update local cache
        if let index = searchAlerts.firstIndex(where: { $0.id == alertId }) {
            searchAlerts[index].isRead = true
        }
        
        print("✅ Marked alert as read: \(alertId)")
    }
    
    /// Create a new search alert
    func createAlert(savedSearchId: String, query: String, resultCount: Int) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw FirebaseError.unauthorized
        }
        
        let alert = SearchAlert(
            userId: userId,
            savedSearchId: savedSearchId,
            query: query,
            resultCount: resultCount
        )
        
        let data: [String: Any] = [
            "userId": alert.userId,
            "savedSearchId": alert.savedSearchId,
            "query": alert.query,
            "resultCount": alert.resultCount,
            "isRead": alert.isRead,
            "createdAt": alert.createdAt
        ]
        
        try await db.collection("searchAlerts").addDocument(data: data)
        
        print("✅ Created search alert for query: \(query)")
    }
    
    // MARK: - Real-time Listener
    
    /// Start listening for saved searches changes
    func startListening() {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ No user ID for saved searches listener")
            return
        }
        
        print("🔊 Starting real-time listener for saved searches...")
        
        listener = db.collection("savedSearches")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Saved searches listener error: \(error)")
                    Task { @MainActor in
                        self.error = error.localizedDescription
                    }
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let searches = snapshot.documents.compactMap { doc -> SavedSearch? in
                    var search = try? doc.data(as: SavedSearch.self)
                    search?.id = doc.documentID
                    return search
                }
                
                Task { @MainActor in
                    self.savedSearches = searches
                    print("✅ Real-time update: \(searches.count) saved searches")
                }
            }
        
        // Also listen for alerts
        alertsListener = db.collection("searchAlerts")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Search alerts listener error: \(error)")
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let alerts = snapshot.documents.compactMap { doc -> SearchAlert? in
                    var alert = try? doc.data(as: SearchAlert.self)
                    alert?.id = doc.documentID
                    return alert
                }
                
                Task { @MainActor in
                    self.searchAlerts = alerts
                    print("✅ Real-time update: \(alerts.count) search alerts")
                }
            }
    }
    
    /// Stop listening for changes
    func stopListening() {
        print("🔇 Stopping saved searches listener...")
        listener?.remove()
        listener = nil
        alertsListener?.remove()
        alertsListener = nil
    }
    
    // MARK: - Cleanup
    
    @MainActor deinit {
        stopListening()
    }
}

// MARK: - Errors

enum SavedSearchError: LocalizedError {
    case alreadySaved
    case notFound
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .alreadySaved:
            return "This search is already saved"
        case .notFound:
            return "Saved search not found"
        case .unauthorized:
            return "You must be signed in to save searches"
        }
    }
}

