//
//  VisitPlanService.swift
//  AMENAPP
//
//  Created by Claude on 2026-02-24.
//  First Visit Companion - Idempotent Visit Plan Management
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import Combine

@MainActor
class VisitPlanService: ObservableObject {
    private let db = Firestore.firestore()
    
    // MARK: - Create Visit Plan (Idempotent)
    
    /// Creates a visit plan for a church service. Idempotent - returns existing plan if already created.
    func createVisitPlan(
        userId: String,
        church: VisitCompanionChurch,
        service: VisitCompanionChurchService,
        serviceDate: Date
    ) async throws -> VisitPlan {
        // Check if plan already exists (idempotent)
        if let existing = try await getVisitPlan(
            userId: userId,
            churchId: church.id ?? "",
            serviceDate: serviceDate
        ) {
            Logger.debug("Visit plan already exists: \(existing.id ?? "unknown")")
            return existing
        }
        
        // Create unique ID for idempotency
        let churchId = church.id ?? UUID().uuidString
        let visitPlanId = "\(userId)_\(churchId)_\(Int(serviceDate.timeIntervalSince1970))"
        
        let now = Timestamp()
        let visitPlan = VisitPlan(
            id: visitPlanId,
            userId: userId,
            churchId: churchId,
            churchName: church.name,
            serviceDate: Timestamp(date: serviceDate),
            serviceTime: service.startTime,
            serviceType: service.serviceType,
            calendarEventId: nil,
            calendarSynced: false,
            reminderScheduled: false,
            reminderNotificationId: nil,
            dayOfReminderScheduled: false,
            dayOfReminderNotificationId: nil,
            churchAddress: church.address.fullAddress,
            churchCoordinates: church.address.coordinates,
            status: .planned,
            visited: false,
            visitedAt: nil,
            autoNoteCreated: false,
            noteId: nil,
            createdAt: now,
            updatedAt: now
        )
        
        // Write to Firestore with explicit ID (idempotent)
        try db.collection("visit_plans")
            .document(visitPlanId)
            .setData(from: visitPlan)
        
        Logger.debug("Created visit plan: \(visitPlanId)")
        return visitPlan
    }
    
    // MARK: - Fetch Visit Plan
    
    /// Gets existing visit plan for a user, church, and service date
    func getVisitPlan(
        userId: String,
        churchId: String,
        serviceDate: Date
    ) async throws -> VisitPlan? {
        let visitPlanId = "\(userId)_\(churchId)_\(Int(serviceDate.timeIntervalSince1970))"
        
        let snapshot = try await db.collection("visit_plans")
            .document(visitPlanId)
            .getDocument()
        
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: VisitPlan.self)
    }
    
    /// Gets all visit plans for a user
    func getUserVisitPlans(userId: String) async throws -> [VisitPlan] {
        let snapshot = try await db.collection("visit_plans")
            .whereField("user_id", isEqualTo: userId)
            .order(by: "service_date", descending: false)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: VisitPlan.self)
        }
    }
    
    /// Gets upcoming visit plans for a user
    func getUpcomingVisitPlans(userId: String) async throws -> [VisitPlan] {
        let now = Timestamp()
        
        let snapshot = try await db.collection("visit_plans")
            .whereField("user_id", isEqualTo: userId)
            .whereField("service_date", isGreaterThan: now)
            .whereField("status", in: [
                VisitPlanStatus.planned.rawValue,
                VisitPlanStatus.reminded.rawValue,
                VisitPlanStatus.dayOf.rawValue
            ])
            .order(by: "service_date", descending: false)
            .limit(to: 10)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: VisitPlan.self)
        }
    }
    
    // MARK: - Update Visit Plan
    
    /// Updates calendar sync status (idempotent)
    func updateCalendarSync(
        visitPlanId: String,
        calendarEventId: String
    ) async throws {
        try await db.collection("visit_plans")
            .document(visitPlanId)
            .updateData([
                "calendar_event_id": calendarEventId,
                "calendar_synced": true,
                "updated_at": Timestamp()
            ])
        
        Logger.debug("Updated calendar sync for visit plan: \(visitPlanId)")
    }
    
    /// Updates reminder notification status (idempotent)
    func updateReminderScheduled(
        visitPlanId: String,
        notificationId: String
    ) async throws {
        try await db.collection("visit_plans")
            .document(visitPlanId)
            .updateData([
                "reminder_notification_id": notificationId,
                "reminder_scheduled": true,
                "status": VisitPlanStatus.reminded.rawValue,
                "updated_at": Timestamp()
            ])
        
        Logger.debug("Updated reminder for visit plan: \(visitPlanId)")
    }
    
    /// Updates day-of reminder status (idempotent)
    func updateDayOfReminderScheduled(
        visitPlanId: String,
        notificationId: String
    ) async throws {
        try await db.collection("visit_plans")
            .document(visitPlanId)
            .updateData([
                "day_of_reminder_notification_id": notificationId,
                "day_of_reminder_scheduled": true,
                "status": VisitPlanStatus.dayOf.rawValue,
                "updated_at": Timestamp()
            ])
        
        Logger.debug("Updated day-of reminder for visit plan: \(visitPlanId)")
    }
    
    /// Marks visit as completed and links to auto-created note (idempotent)
    func markVisited(
        visitPlanId: String,
        noteId: String?
    ) async throws {
        var updateData: [String: Any] = [
            "visited": true,
            "visited_at": Timestamp(),
            "status": VisitPlanStatus.visited.rawValue,
            "updated_at": Timestamp()
        ]
        
        if let noteId = noteId {
            updateData["note_id"] = noteId
            updateData["auto_note_created"] = true
        }
        
        try await db.collection("visit_plans")
            .document(visitPlanId)
            .updateData(updateData)
        
        Logger.debug("Marked visit plan as visited: \(visitPlanId)")
    }
    
    /// Cancels a visit plan (idempotent)
    func cancelVisitPlan(visitPlanId: String) async throws {
        try await db.collection("visit_plans")
            .document(visitPlanId)
            .updateData([
                "status": VisitPlanStatus.cancelled.rawValue,
                "updated_at": Timestamp()
            ])
        
        Logger.debug("Cancelled visit plan: \(visitPlanId)")
    }
    
    // MARK: - Real-time Listener
    
    /// Listen to upcoming visit plans for a user
    func listenToUpcomingVisitPlans(
        userId: String,
        onUpdate: @escaping ([VisitPlan]) -> Void
    ) -> ListenerRegistration {
        let now = Timestamp()
        
        return db.collection("visit_plans")
            .whereField("user_id", isEqualTo: userId)
            .whereField("service_date", isGreaterThan: now)
            .whereField("status", in: [
                VisitPlanStatus.planned.rawValue,
                VisitPlanStatus.reminded.rawValue,
                VisitPlanStatus.dayOf.rawValue
            ])
            .order(by: "service_date", descending: false)
            .limit(to: 10)
            .addSnapshotListener { snapshot, error in
                guard let snapshot = snapshot, error == nil else {
                    Logger.error("Error listening to visit plans: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                
                let plans = snapshot.documents.compactMap { doc in
                    try? doc.data(as: VisitPlan.self)
                }
                
                onUpdate(plans)
            }
    }
}
