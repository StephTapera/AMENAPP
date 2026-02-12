//
//  HelpSupportView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import MessageUI
import FirebaseAuth
import FirebaseFirestore

struct HelpSupportView: View {
    @State private var showContactSheet = false
    @State private var selectedHelpTopic: HelpTopic?
    @State private var showMailComposer = false
    @State private var showMailError = false
    @State private var showFeedbackForm = false
    @State private var showBugReportForm = false
    
    var body: some View {
        List {
            // Quick Help Section
            Section {
                ForEach(HelpTopic.allCases, id: \.self) { topic in
                    Button {
                        selectedHelpTopic = topic
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: topic.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(topic.color)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.title)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                
                                Text(topic.subtitle)
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("HELP TOPICS")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Contact Support Section
            Section {
                Button {
                    if MFMailComposeViewController.canSendMail() {
                        showMailComposer = true
                    } else {
                        showMailError = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Email Support")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text("support@amenapp.com")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Link(destination: URL(string: "https://amenapp.com/support")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.cyan)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visit Help Center")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text("Browse our knowledge base")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("CONTACT US")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Community Section
            Section {
                Link(destination: URL(string: "https://amenapp.com/community")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.purple)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Community Forum")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text("Connect with other users")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("COMMUNITY")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
            
            // Feedback Section
            Section {
                Button {
                    showFeedbackForm = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Send Feedback")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text("Help us improve AMEN")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                Button {
                    showBugReportForm = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report a Bug")
                                .font(.custom("OpenSans-SemiBold", size: 15))
                                .foregroundStyle(.primary)
                            
                            Text("Let us know about issues")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("FEEDBACK")
                    .font(.custom("OpenSans-Bold", size: 12))
            }
        }
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedHelpTopic) { topic in
            HelpTopicDetailView(topic: topic)
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposeView()
        }
        .alert("Cannot Send Email", isPresented: $showMailError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please configure an email account in your device settings or contact us at support@amenapp.com")
        }
        .sheet(isPresented: $showFeedbackForm) {
            FeedbackFormView()
        }
        .sheet(isPresented: $showBugReportForm) {
            BugReportFormView()
        }
    }
}

// MARK: - Help Topics

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted = "Getting Started"
    case account = "Account & Profile"
    case privacy = "Privacy & Safety"
    case posts = "Posts & Testimonies"
    case communities = "Communities"
    case messaging = "Messaging"
    case prayer = "Prayer Requests"
    case troubleshooting = "Troubleshooting"
    
    var id: String { rawValue }
    var title: String { rawValue }
    
    var subtitle: String {
        switch self {
        case .gettingStarted: return "Learn the basics"
        case .account: return "Manage your account"
        case .privacy: return "Stay safe and secure"
        case .posts: return "Share your faith journey"
        case .communities: return "Join and create groups"
        case .messaging: return "Connect with others"
        case .prayer: return "Request and offer prayers"
        case .troubleshooting: return "Fix common issues"
        }
    }
    
    var icon: String {
        switch self {
        case .gettingStarted: return "flag.fill"
        case .account: return "person.circle.fill"
        case .privacy: return "lock.shield.fill"
        case .posts: return "doc.text.fill"
        case .communities: return "person.3.fill"
        case .messaging: return "message.fill"
        case .prayer: return "hands.sparkles.fill"
        case .troubleshooting: return "wrench.and.screwdriver.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .gettingStarted: return .green
        case .account: return .blue
        case .privacy: return .red
        case .posts: return .orange
        case .communities: return .purple
        case .messaging: return .cyan
        case .prayer: return .indigo
        case .troubleshooting: return .gray
        }
    }
    
    var content: String {
        switch self {
        case .gettingStarted:
            return """
            Welcome to AMEN! Here's how to get started:
            
            1. Complete Your Profile
            • Add a profile photo
            • Write a bio
            • Share your faith journey
            
            2. Follow Others
            • Search for friends
            • Discover communities
            • Connect with believers
            
            3. Share Your Story
            • Post testimonies
            • Share prayer requests
            • Encourage others
            
            4. Join Communities
            • Find groups that interest you
            • Participate in discussions
            • Build meaningful connections
            """
        
        case .account:
            return """
            Managing Your Account:
            
            Profile Settings
            • Update your display name and username
            • Add or change profile photo
            • Edit your bio and interests
            
            Account Security
            • Change your password regularly
            • Enable two-factor authentication
            • Review login activity
            
            Privacy Controls
            • Make your account private
            • Control who can message you
            • Manage blocked users
            """
        
        case .privacy:
            return """
            Your Privacy & Safety:
            
            Privacy Controls
            • Private account option
            • Control message permissions
            • Hide online status
            
            Safety Features
            • Block and report users
            • Mute conversations
            • Filter comments
            
            Content Safety
            • Report inappropriate content
            • Community guidelines
            • Moderation tools
            """
        
        case .posts:
            return """
            Posts & Testimonies:
            
            Creating Posts
            • Share text, photos, and videos
            • Add hashtags for discovery
            • Tag other users
            
            Testimonies
            • Share answered prayers
            • Encourage others
            • Build your faith story
            
            Engagement
            • Amen posts you love
            • Comment and discuss
            • Share with your community
            """
        
        case .communities:
            return """
            Communities:
            
            Finding Communities
            • Search by interests
            • Browse recommendations
            • Join public or private groups
            
            Creating Communities
            • Start your own group
            • Set community guidelines
            • Invite members
            
            Participating
            • Share in group discussions
            • Organize events
            • Support fellow members
            """
        
        case .messaging:
            return """
            Messaging:
            
            Direct Messages
            • Send private messages
            • Share photos and media
            • Create group chats
            
            Message Settings
            • Control who can message you
            • Read receipts
            • Notification preferences
            
            Safety
            • Block unwanted messages
            • Report spam or abuse
            • Mute conversations
            """
        
        case .prayer:
            return """
            Prayer Requests:
            
            Requesting Prayer
            • Share your prayer needs
            • Set privacy preferences
            • Update answered prayers
            
            Praying for Others
            • Browse prayer requests
            • Commit to pray
            • Send encouragement
            
            Prayer Groups
            • Join prayer circles
            • Schedule prayer times
            • Track prayer journeys
            """
        
        case .troubleshooting:
            return """
            Common Issues:
            
            App Not Loading
            • Check internet connection
            • Force quit and restart app
            • Update to latest version
            
            Can't Post or Comment
            • Check content guidelines
            • Verify internet connection
            • Clear app cache
            
            Notifications Not Working
            • Enable notifications in Settings
            • Check Do Not Disturb mode
            • Update notification preferences
            
            Login Issues
            • Verify email and password
            • Reset password if needed
            • Contact support for help
            """
        }
    }
}

// MARK: - Help Topic Detail View

struct HelpTopicDetailView: View {
    let topic: HelpTopic
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Icon
                    HStack {
                        Spacer()
                        Image(systemName: topic.icon)
                            .font(.system(size: 60))
                            .foregroundStyle(topic.color)
                            .padding(.top, 20)
                        Spacer()
                    }
                    
                    // Content
                    Text(topic.content)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .foregroundStyle(.primary)
                        .lineSpacing(8)
                        .padding(.horizontal)
                    
                    // Still Need Help Button
                    VStack(spacing: 16) {
                        Divider()
                            .padding(.horizontal)
                        
                        Text("Still need help?")
                            .font(.custom("OpenSans-SemiBold", size: 16))
                        
                        Button {
                            // Open support email
                        } label: {
                            HStack {
                                Image(systemName: "envelope.fill")
                                Text("Contact Support")
                                    .font(.custom("OpenSans-SemiBold", size: 16))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
}

// MARK: - Mail Composer

struct MailComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    
    init() {}
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(["support@amenapp.com"])
        composer.setSubject("AMEN App Support Request")
        
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let iosVersion = UIDevice.current.systemVersion
        
        let body = """
        
        
        ---
        Please describe your issue or question above this line.
        
        App Version: \(appVersion) (\(buildNumber))
        iOS Version: \(iosVersion)
        Device: \(UIDevice.current.model)
        """
        
        composer.setMessageBody(body, isHTML: false)
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        
        init(_ parent: MailComposeView) {
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
}

// MARK: - Feedback Form View

struct FeedbackFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var feedbackText = ""
    @State private var feedbackType: FeedbackType = .general
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum FeedbackType: String, CaseIterable {
        case general = "General Feedback"
        case feature = "Feature Request"
        case improvement = "Improvement"
        case compliment = "Compliment"
        
        var icon: String {
            switch self {
            case .general: return "text.bubble.fill"
            case .feature: return "star.fill"
            case .improvement: return "arrow.up.circle.fill"
            case .compliment: return "heart.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .general: return .blue
            case .feature: return .purple
            case .improvement: return .orange
            case .compliment: return .pink
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 20)
                        
                        Text("Send Feedback")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Help us make AMEN better for everyone")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    // Feedback Type Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Feedback Type")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(FeedbackType.allCases, id: \.self) { type in
                                    Button {
                                        feedbackType = type
                                        HapticManager.impact(style: .light)
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: type.icon)
                                                .font(.system(size: 24))
                                                .foregroundStyle(feedbackType == type ? type.color : .gray)
                                            
                                            Text(type.rawValue)
                                                .font(.custom("OpenSans-SemiBold", size: 12))
                                                .foregroundStyle(feedbackType == type ? .primary : .secondary)
                                        }
                                        .frame(width: 100, height: 80)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(feedbackType == type ? type.color.opacity(0.1) : Color(.systemBackground))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(feedbackType == type ? type.color : Color.gray.opacity(0.2), lineWidth: feedbackType == type ? 2 : 1)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    // Feedback Text
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Feedback")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $feedbackText)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .frame(height: 150)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color(.systemBackground))
                            
                            if feedbackText.isEmpty {
                                Text("Tell us what you think...")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        
                        Text("\(feedbackText.count)/500 characters")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    
                    // Submit Button
                    Button {
                        submitFeedback()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Submit Feedback")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(feedbackText.count >= 10 ? feedbackType.color : Color.gray)
                        )
                    }
                    .disabled(feedbackText.count < 10 || isLoading)
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert("Thank You!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your feedback has been received. We appreciate you helping us improve AMEN!")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func submitFeedback() {
        guard feedbackText.count >= 10, feedbackText.count <= 500 else { return }
        
        isLoading = true
        
        Task {
            do {
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "Feedback", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                let iosVersion = UIDevice.current.systemVersion
                let deviceModel = UIDevice.current.model
                
                let feedbackData: [String: Any] = [
                    "userId": userId,
                    "type": feedbackType.rawValue,
                    "feedback": feedbackText,
                    "appVersion": appVersion,
                    "buildNumber": buildNumber,
                    "iosVersion": iosVersion,
                    "deviceModel": deviceModel,
                    "createdAt": FieldValue.serverTimestamp(),
                    "status": "new"
                ]
                
                try await Firestore.firestore().collection("feedback").addDocument(data: feedbackData)
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                    HapticManager.notification(type: .success)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
}

// MARK: - Bug Report Form View

struct BugReportFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var bugTitle = ""
    @State private var bugDescription = ""
    @State private var stepsToReproduce = ""
    @State private var bugSeverity: BugSeverity = .medium
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var includeScreenshot = false
    
    enum BugSeverity: String, CaseIterable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        case critical = "Critical"
        
        var color: Color {
            switch self {
            case .low: return .green
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .low: return "info.circle.fill"
            case .medium: return "exclamationmark.circle.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                            .padding(.top, 20)
                        
                        Text("Report a Bug")
                            .font(.custom("OpenSans-Bold", size: 28))
                        
                        Text("Help us fix issues and improve stability")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    
                    // Bug Title
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bug Title")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        TextField("Brief description of the issue", text: $bugTitle)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)
                    
                    // Severity Picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Severity Level")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 12) {
                            ForEach(BugSeverity.allCases, id: \.self) { severity in
                                Button {
                                    bugSeverity = severity
                                    HapticManager.impact(style: .light)
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: severity.icon)
                                            .font(.system(size: 20))
                                            .foregroundStyle(bugSeverity == severity ? severity.color : .gray)
                                        
                                        Text(severity.rawValue)
                                            .font(.custom("OpenSans-SemiBold", size: 11))
                                            .foregroundStyle(bugSeverity == severity ? .primary : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(bugSeverity == severity ? severity.color.opacity(0.1) : Color(.systemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(bugSeverity == severity ? severity.color : Color.gray.opacity(0.2), lineWidth: bugSeverity == severity ? 2 : 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Bug Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What happened?")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $bugDescription)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .frame(height: 120)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color(.systemBackground))
                            
                            if bugDescription.isEmpty {
                                Text("Describe the bug in detail...")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Steps to Reproduce
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Steps to Reproduce")
                            .font(.custom("OpenSans-SemiBold", size: 14))
                            .foregroundStyle(.secondary)
                        
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $stepsToReproduce)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .frame(height: 120)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(Color(.systemBackground))
                            
                            if stepsToReproduce.isEmpty {
                                Text("1. Go to...\n2. Tap on...\n3. See error...")
                                    .font(.custom("OpenSans-Regular", size: 15))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Device Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Device Information (Auto-included)")
                                .font(.custom("OpenSans-Bold", size: 13))
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            DeviceInfoRow(label: "App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            DeviceInfoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            DeviceInfoRow(label: "iOS Version", value: UIDevice.current.systemVersion)
                            DeviceInfoRow(label: "Device", value: UIDevice.current.model)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                    )
                    .padding(.horizontal)
                    
                    // Submit Button
                    Button {
                        submitBugReport()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Submit Bug Report")
                                    .font(.custom("OpenSans-Bold", size: 16))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isValidReport ? Color.red : Color.gray)
                        )
                    }
                    .disabled(!isValidReport || isLoading)
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Report Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
            .alert("Thank You!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your bug report has been submitted. Our team will investigate this issue.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var isValidReport: Bool {
        !bugTitle.isEmpty && !bugDescription.isEmpty && bugDescription.count >= 20
    }
    
    private func submitBugReport() {
        guard isValidReport else { return }
        
        isLoading = true
        
        Task {
            do {
                guard let userId = Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "BugReport", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
                }
                
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
                let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
                let iosVersion = UIDevice.current.systemVersion
                let deviceModel = UIDevice.current.model
                
                let bugReportData: [String: Any] = [
                    "userId": userId,
                    "title": bugTitle,
                    "description": bugDescription,
                    "stepsToReproduce": stepsToReproduce,
                    "severity": bugSeverity.rawValue,
                    "appVersion": appVersion,
                    "buildNumber": buildNumber,
                    "iosVersion": iosVersion,
                    "deviceModel": deviceModel,
                    "createdAt": FieldValue.serverTimestamp(),
                    "status": "new"
                ]
                
                try await Firestore.firestore().collection("bug_reports").addDocument(data: bugReportData)
                
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                    HapticManager.notification(type: .success)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                    HapticManager.notification(type: .error)
                }
            }
        }
    }
}

struct DeviceInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.custom("OpenSans-SemiBold", size: 12))
                .foregroundStyle(.primary)
        }
    }
}

#Preview("Help & Support") {
    NavigationStack {
        HelpSupportView()
    }
}
