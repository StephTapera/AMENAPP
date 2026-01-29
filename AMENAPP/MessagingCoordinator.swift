//
//  MessagingCoordinator.swift
//  AMENAPP
//
//  Handles navigation to messages from anywhere in the app
//

import Foundation
import SwiftUI
import Combine

/// Coordinator for handling message-related navigation throughout the app
@MainActor
class MessagingCoordinator: ObservableObject {
    static let shared = MessagingCoordinator()
    
    /// Published property to trigger opening a specific conversation
    @Published var conversationToOpen: String?
    
    /// Published property to trigger switching to messages tab
    @Published var shouldOpenMessagesTab = false
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationListeners()
    }
    
    /// Setup notification listeners for message-related actions
    private func setupNotificationListeners() {
        NotificationCenter.default.publisher(for: .openConversation)
            .sink { [weak self] notification in
                guard let self = self else { return }
                
                if let conversationId = notification.userInfo?["conversationId"] as? String {
                    self.openConversation(conversationId)
                }
            }
            .store(in: &cancellables)
    }
    
    /// Open a specific conversation
    func openConversation(_ conversationId: String) {
        conversationToOpen = conversationId
        shouldOpenMessagesTab = true
        
        // Reset after a short delay to allow navigation to complete
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            conversationToOpen = nil
            shouldOpenMessagesTab = false
        }
    }
    
    /// Open messages tab (without specific conversation)
    func openMessagesTab() {
        shouldOpenMessagesTab = true
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            shouldOpenMessagesTab = false
        }
    }
}
