//
//  HelpSupportView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//

import SwiftUI
import MessageUI

struct HelpSupportView: View {
    @State private var showContactSheet = false
    @State private var selectedHelpTopic: HelpTopic?
    @State private var showMailComposer = false
    @State private var showMailError = false
    
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
                    // Open feedback form
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
                    // Report a bug
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

#Preview {
    NavigationStack {
        HelpSupportView()
    }
}
