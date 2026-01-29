//
//  DatingNotificationService.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import Foundation
import Combine
import UserNotifications
import UIKit
import SwiftUI

@MainActor
class DatingNotificationService: ObservableObject {
    static let shared = DatingNotificationService()
    
    @Published var newMatches: [DatingMatch] = []
    @Published var newMessages: [DatingMessage] = []
    @Published var unreadMatchCount: Int = 0
    @Published var unreadMessageCount: Int = 0
    @Published var isConnected: Bool = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    // MARK: - Connection Management
    
    func connect() {
        guard !isConnected else { return }
        
        // TODO: Replace with actual WebSocket URL
        // guard let url = URL(string: "wss://your-backend.com/dating/notifications") else { return }
        
        // webSocketTask = URLSession.shared.webSocketTask(with: url)
        // webSocketTask?.resume()
        // receiveMessage()
        
        isConnected = true
        print("🔔 Dating notifications connected")
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        print("🔔 Dating notifications disconnected")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                Task { @MainActor in
                    await self.handleWebSocketMessage(message)
                    self.receiveMessage() // Continue listening
                }
                
            case .failure(let error):
                print("❌ WebSocket error: \(error)")
                Task { @MainActor in
                    self.isConnected = false
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let text):
            await processNotification(from: text)
            
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                await processNotification(from: text)
            }
            
        @unknown default:
            break
        }
    }
    
    private func processNotification(from jsonString: String) async {
        guard let data = jsonString.data(using: .utf8) else { return }
        
        // TODO: Parse notification based on your backend structure
        // For example:
        // {
        //   "type": "new_match",
        //   "data": { match object }
        // }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let type = json["type"] as? String ?? ""
                
                switch type {
                case "new_match":
                    await handleNewMatch(json["data"] as? [String: Any])
                    
                case "new_message":
                    await handleNewMessage(json["data"] as? [String: Any])
                    
                case "profile_like":
                    await handleProfileLike(json["data"] as? [String: Any])
                    
                default:
                    break
                }
            }
        } catch {
            print("❌ Failed to parse notification: \(error)")
        }
    }
    
    // MARK: - Notification Handlers
    
    private func handleNewMatch(_ data: [String: Any]?) async {
        // Parse match data and add to newMatches
        // Show local notification
        await showLocalNotification(
            title: "New Match! 💕",
            body: "You have a new match. Start chatting now!",
            identifier: "new_match"
        )
        
        unreadMatchCount += 1
    }
    
    private func handleNewMessage(_ data: [String: Any]?) async {
        // Parse message data and add to newMessages
        await showLocalNotification(
            title: "New Message 💬",
            body: "You have a new message from a match",
            identifier: "new_message"
        )
        
        unreadMessageCount += 1
    }
    
    private func handleProfileLike(_ data: [String: Any]?) async {
        // Someone liked your profile
        await showLocalNotification(
            title: "Someone Likes You! ❤️",
            body: "Someone is interested in your profile",
            identifier: "profile_like"
        )
    }
    
    // MARK: - Push Notifications
    
    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            if granted {
                await registerForRemoteNotifications()
            }
            
            return granted
        } catch {
            print("❌ Notification permission error: \(error)")
            return false
        }
    }
    
    private func registerForRemoteNotifications() async {
        await MainActor.run {
            #if !targetEnvironment(simulator)
            UIApplication.shared.registerForRemoteNotifications()
            #endif
        }
    }
    
    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        // TODO: Send token to backend
        // Task {
        //     try await APIClient.post("/api/dating/notifications/register", body: ["token": tokenString])
        // }
        
        print("📱 Device token: \(tokenString)")
    }
    
    private func showLocalNotification(title: String, body: String, identifier: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: unreadMatchCount + unreadMessageCount)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("❌ Failed to show notification: \(error)")
        }
    }
    
    // MARK: - Badge Management
    
    func clearBadge() {
        unreadMatchCount = 0
        unreadMessageCount = 0
        
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
    
    func markMatchesAsRead() {
        unreadMatchCount = 0
        updateBadge()
    }
    
    func markMessagesAsRead() {
        unreadMessageCount = 0
        updateBadge()
    }
    
    private func updateBadge() {
        Task { @MainActor in
            UIApplication.shared.applicationIconBadgeNumber = unreadMatchCount + unreadMessageCount
        }
    }
    
    // MARK: - Manual Polling (fallback if WebSocket not available)
    
    func startPolling(interval: TimeInterval = 30) {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.pollForUpdates()
                }
            }
            .store(in: &cancellables)
    }
    
    func stopPolling() {
        cancellables.removeAll()
    }
    
    private func pollForUpdates() async {
        // TODO: Implement polling endpoint
        // let updates = try? await APIClient.get("/api/dating/notifications/poll")
    }
}

// MARK: - In-App Notification Banner

struct DatingNotificationBanner: Identifiable {
    let id = UUID()
    let type: DatingNotificationType
    let title: String
    let message: String
    let icon: String
    let color: Color
    let action: (() -> Void)?
    
    init(
        type: DatingNotificationType,
        title: String,
        message: String,
        icon: String = "heart.fill",
        color: Color = .pink,
        action: (() -> Void)? = nil
    ) {
        self.type = type
        self.title = title
        self.message = message
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    static func newMatch(profile: DatingProfile) -> DatingNotificationBanner {
        return DatingNotificationBanner(
            type: .newMatch,
            title: "New Match! 💕",
            message: "You matched with \(profile.name)",
            icon: "heart.fill",
            color: .pink
        )
    }
    
    static func newMessage(from name: String) -> DatingNotificationBanner {
        return DatingNotificationBanner(
            type: .newMessage,
            title: "New Message",
            message: "\(name) sent you a message",
            icon: "message.fill",
            color: .blue
        )
    }
    
    static func profileLike() -> DatingNotificationBanner {
        return DatingNotificationBanner(
            type: .profileLike,
            title: "Someone Likes You!",
            message: "Check your matches to see who",
            icon: "heart.fill",
            color: .red
        )
    }
}

// MARK: - Notification Manager for In-App Banners

@MainActor
class InAppNotificationManager: ObservableObject {
    static let shared = InAppNotificationManager()
    
    @Published var currentBanner: DatingNotificationBanner?
    @Published var bannerQueue: [DatingNotificationBanner] = []
    
    private init() {}
    
    func show(_ banner: DatingNotificationBanner) {
        if currentBanner == nil {
            currentBanner = banner
            
            // Auto-dismiss after 4 seconds
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                dismiss()
            }
        } else {
            bannerQueue.append(banner)
        }
    }
    
    func dismiss() {
        currentBanner = nil
        
        // Show next banner if available
        if !bannerQueue.isEmpty {
            currentBanner = bannerQueue.removeFirst()
            
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                dismiss()
            }
        }
    }
}
