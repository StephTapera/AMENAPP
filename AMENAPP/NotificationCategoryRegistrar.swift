// NotificationCategoryRegistrar.swift
// AMENAPP
//
// Centralized UNNotificationCategory accumulator.
//
// PROBLEM: five services each called setNotificationCategories([...]) independently.
// That API REPLACES the entire registered set on every call, so the last caller won
// and silently dropped every other service's action buttons (Reply, Attend, Get
// Directions, Take Break, etc.).
//
// SOLUTION: every service calls NotificationCategoryRegistrar.shared.register(_:)
// instead. Each call merges new categories into an internal map keyed by identifier
// and immediately applies the full accumulated union via setNotificationCategories.
// Later registrations safely add to the set rather than replacing it.

import UserNotifications

@MainActor
final class NotificationCategoryRegistrar {
    static let shared = NotificationCategoryRegistrar()
    private init() {}

    private var categoryMap: [String: UNNotificationCategory] = [:]

    /// Add or update categories and immediately apply the full accumulated set.
    /// Safe to call from any service at any time — each call is additive.
    func register(_ categories: [UNNotificationCategory]) {
        for category in categories {
            categoryMap[category.identifier] = category
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categoryMap.values))
    }
}
