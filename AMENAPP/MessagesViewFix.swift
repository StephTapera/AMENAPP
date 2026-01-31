// 🔧 SHEET PRESENTATION FIX FOR MESSAGESVIEW
// 
// The issue: Multiple .sheet() modifiers on the same view can conflict
// The solution: Use a single sheet with an enum to control what's shown

import SwiftUI
import FirebaseAuth

// MARK: - Sheet Type Enum
// NOTE: This enum is now defined in MessagesView.swift - don't duplicate it!

/*
enum MessageSheetType: Identifiable {
    case chat(ChatConversation)
    case newMessage
    case createGroup
    case settings
    
    var id: String {
        switch self {
        case .chat(let conversation):
            return "chat_\(conversation.id)"
        case .newMessage:
            return "newMessage"
        case .createGroup:
            return "createGroup"
        case .settings:
            return "settings"
        }
    }
}
*/

// MARK: - Fixed MessagesView with Single Sheet

// REPLACE your existing MessagesView body with this pattern:

/*

struct MessagesView: View {
    @StateObject private var messagingService = FirebaseMessagingService.shared
    @StateObject private var messagingCoordinator = MessagingCoordinator.shared
    @State private var searchText = ""
    @State private var selectedTab: MessageTab = .messages
    @State private var messageRequests: [MessageRequest] = []
    @State private var archivedConversations: [ChatConversation] = []
    @State private var conversationToDelete: ChatConversation?
    @State private var isArchiving = false
    @State private var isDeleting = false
    
    // REPLACE these separate @State vars:
    // @State private var selectedConversation: ChatConversation?
    // @State private var showNewMessage = false
    // @State private var showCreateGroup = false
    // @State private var showChatView = false
    // @State private var showSettings = false
    // @State private var showDeleteConfirmation = false
    
    // WITH this single @State var:
    @State private var activeSheet: MessageSheetType?
    @State private var showDeleteConfirmation = false
    
    enum MessageTab {
        case messages
        case requests
        case archived
    }
    
    var body: some View {
        NavigationStack {
            mainContentView
                .navigationBarHidden(true)
                // SINGLE SHEET MODIFIER - handles all sheets
                .sheet(item: $activeSheet) { sheetType in
                    sheetView(for: sheetType)
                }
                .confirmationDialog(
                    "Delete Conversation",
                    isPresented: $showDeleteConfirmation,
                    presenting: conversationToDelete
                ) { conversation in
                    Button("Delete", role: .destructive) {
                        Task {
                            await deleteConversation(conversation)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { conversation in
                    Text("Are you sure you want to delete the conversation with \(conversation.name)?")
                }
                .task {
                    messagingService.startListeningToConversations()
                    await loadMessageRequests()
                    await loadArchivedConversations()
                    startListeningToMessageRequests()
                }
                .onDisappear {
                    messagingService.stopListeningToConversations()
                    stopListeningToMessageRequests()
                }
                .onChange(of: messagingCoordinator.conversationToOpen) { oldValue, newValue in
                    if let conversationId = newValue {
                        handleCoordinatorRequest(conversationId: conversationId)
                    }
                }
        }
    }
    
    // MARK: - Sheet View Builder
    
    @ViewBuilder
    private func sheetView(for type: MessageSheetType) -> some View {
        switch type {
        case .chat(let conversation):
            ModernConversationDetailView(conversation: conversation)
                .onAppear {
                    print("\n🎬 SHEET PRESENTING: Chat")
                    print("   - Conversation: \(conversation.name)")
                }
        
        case .newMessage:
            MessagingUserSearchView { firebaseUser in
                let selectedUser = SearchableUser(from: firebaseUser)
                Task {
                    await startConversation(with: selectedUser)
                }
            }
            .onAppear {
                print("\n🎬 SHEET PRESENTING: New Message")
            }
        
        case .createGroup:
            CreateGroupView()
                .onAppear {
                    print("\n🎬 SHEET PRESENTING: Create Group")
                }
        
        case .settings:
            MessageSettingsView()
                .onAppear {
                    print("\n🎬 SHEET PRESENTING: Settings")
                }
        }
    }
    
    // MARK: - Main Content (keep existing implementation)
    
    private var mainContentView: some View {
        // ... your existing mainContentView implementation
        Text("Your existing content here")
    }
    
    // MARK: - Helper Functions
    
    /// Open chat with conversation
    private func openChat(with conversation: ChatConversation) {
        print("\n💬 OPENING CHAT")
        print("   - Conversation: \(conversation.name)")
        print("   - ID: \(conversation.id)")
        
        // Set the sheet to show chat
        activeSheet = .chat(conversation)
        
        print("   - activeSheet set to: \(activeSheet?.id ?? "nil")")
    }
    
    /// Start a new conversation with a user
    private func startConversation(with user: SearchableUser) async {
        print("\n🚀 START CONVERSATION")
        print("   - User: \(user.displayName)")
        print("   - ID: \(user.id)")
        
        do {
            let conversationId = try await messagingService.getOrCreateDirectConversation(
                withUserId: user.id,
                userName: user.displayName
            )
            
            print("✅ Got conversation ID: \(conversationId)")
            
            // Dismiss search sheet
            await MainActor.run {
                activeSheet = nil
            }
            
            // Wait for sheet dismissal
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            // Find or create conversation object
            if let conversation = messagingService.conversations.first(where: { $0.id == conversationId }) {
                print("✅ Found conversation in list")
                await MainActor.run {
                    activeSheet = .chat(conversation)
                }
            } else {
                print("⚠️ Creating temp conversation")
                let tempConversation = ChatConversation(
                    id: conversationId,
                    name: user.displayName,
                    lastMessage: "",
                    timestamp: "Just now",
                    isGroup: false,
                    unreadCount: 0,
                    avatarColor: .blue
                )
                
                await MainActor.run {
                    activeSheet = .chat(tempConversation)
                }
            }
            
            print("✅ CONVERSATION OPENED")
            
        } catch {
            print("❌ ERROR: \(error)")
            await MainActor.run {
                activeSheet = nil
            }
        }
    }
    
    /// Handle coordinator request to open conversation
    private func handleCoordinatorRequest(conversationId: String) {
        print("\n📞 COORDINATOR REQUEST")
        print("   - Conversation ID: \(conversationId)")
        
        if let conversation = messagingService.conversations.first(where: { $0.id == conversationId }) {
            print("✅ Found conversation")
            openChat(with: conversation)
        } else {
            print("⚠️ Conversation not found in list")
        }
        
        // Clear the request
        messagingCoordinator.conversationToOpen = nil
    }
    
    // MARK: - Placeholder Functions (keep your existing implementations)
    
    private func loadMessageRequests() async {
        // Your existing implementation
    }
    
    private func loadArchivedConversations() async {
        // Your existing implementation
    }
    
    private func startListeningToMessageRequests() {
        // Your existing implementation
    }
    
    private func stopListeningToMessageRequests() {
        // Your existing implementation
    }
    
    private func deleteConversation(_ conversation: ChatConversation) async {
        // Your existing implementation
    }
}

*/

// MARK: - How to Apply This Fix

/*

STEP 1: In MessagesView.swift, REPLACE these lines:

    @State private var selectedConversation: ChatConversation?
    @State private var showNewMessage = false
    @State private var showCreateGroup = false
    @State private var showChatView = false
    @State private var showSettings = false

WITH:

    @State private var activeSheet: MessageSheetType?


STEP 2: REMOVE these modifiers:

    .modifier(ChatSheetModifier(...))
    .modifier(SheetsModifier(...))


STEP 3: ADD the single sheet modifier to your body:

    .sheet(item: $activeSheet) { sheetType in
        sheetView(for: sheetType)
    }


STEP 4: UPDATE all places that set showChatView = true:

REPLACE:
    selectedConversation = conversation
    showChatView = true

WITH:
    activeSheet = .chat(conversation)


STEP 5: UPDATE all places that set showNewMessage = true:

REPLACE:
    showNewMessage = true

WITH:
    activeSheet = .newMessage


STEP 6: UPDATE all places that set showCreateGroup = true:

REPLACE:
    showCreateGroup = true

WITH:
    activeSheet = .createGroup


STEP 7: UPDATE all places that set showSettings = true:

REPLACE:
    showSettings = true

WITH:
    activeSheet = .settings


STEP 8: ADD the sheetView function from above


STEP 9: UPDATE startConversation function to use activeSheet


STEP 10: Clean build and test!

*/

// MARK: - Quick Test

/*

Add this test button to verify sheets work:

Button("🧪 TEST SHEETS") {
    print("🧪 Testing sheet presentation...")
    
    let testConversation = ChatConversation(
        id: "test123",
        name: "Test User",
        lastMessage: "Test message",
        timestamp: "Now",
        isGroup: false,
        unreadCount: 0,
        avatarColor: .blue
    )
    
    activeSheet = .chat(testConversation)
    
    print("🧪 activeSheet set to: \(activeSheet?.id ?? "nil")")
}
.padding()
.background(Color.green.opacity(0.3))
.cornerRadius(8)

*/

// MARK: - Why This Fixes The Issue

/*

PROBLEM:
Multiple .sheet() modifiers on the same view hierarchy can cause SwiftUI to:
- Not present any sheets at all
- Present the wrong sheet
- Get stuck in a broken state

SOLUTION:
Using a single .sheet(item:) with an enum:
✅ Only one sheet modifier - no conflicts
✅ SwiftUI clearly knows which sheet to present
✅ Type-safe sheet content
✅ Easy to debug (print activeSheet value)
✅ Proper dismissal handling

*/

// MARK: - Additional Debug Logging
// NOTE: This extension should be added to MessagesView.swift if needed

/*
extension MessageSheetType {
    var debugDescription: String {
        switch self {
        case .chat(let conv):
            return "Chat[\(conv.name)]"
        case .newMessage:
            return "NewMessage"
        case .createGroup:
            return "CreateGroup"
        case .settings:
            return "Settings"
        }
    }
}
*/

// Add to body:
/*
.onChange(of: activeSheet) { oldValue, newValue in
    print("\n🔄 activeSheet CHANGED")
    print("   - Old: \(oldValue?.debugDescription ?? "nil")")
    print("   - New: \(newValue?.debugDescription ?? "nil")")
}
*/
