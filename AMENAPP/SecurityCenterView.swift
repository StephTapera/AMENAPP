//
//  SecurityCenterView.swift
//  AMENAPP
//
//  Comprehensive security dashboard for login history, sessions, and account security
//

import SwiftUI

struct SecurityCenterView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var securityService = SecurityService.shared
    @State private var selectedTab: SecurityTab = .sessions
    @State private var showRevokeAllConfirmation = false
    @State private var sessionToRevoke: ActiveSession?
    @State private var showRevokeConfirmation = false
    
    enum SecurityTab: String, CaseIterable {
        case sessions = "Sessions"
        case loginHistory = "Login History"
        case events = "Activity"
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    
                    // Tab Selector
                    tabSelector
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    
                    // Content based on selected tab
                    switch selectedTab {
                    case .sessions:
                        sessionsView
                    case .loginHistory:
                        loginHistoryView
                    case .events:
                        eventsView
                    }
                }
            }
            .navigationTitle("Security & Access")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await securityService.fetchActiveSessions()
                await securityService.fetchLoginHistory()
                await securityService.fetchSecurityEvents()
            }
            .alert("Revoke Session?", isPresented: $showRevokeConfirmation, presenting: sessionToRevoke) { session in
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    Task {
                        await securityService.revokeSession(session.id)
                    }
                }
            } message: { session in
                Text("You'll be logged out from \(session.displayName).")
            }
            .alert("Log Out All Devices?", isPresented: $showRevokeAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out All", role: .destructive) {
                    Task {
                        await securityService.revokeAllSessions()
                    }
                }
            } message: {
                Text("You'll stay logged in on this device, but all other sessions will be ended.")
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 8) {
            ForEach(SecurityTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(AMENFont.medium(14))
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab
                                ? Color.blue
                                : Color.gray.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 20)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    // MARK: - Sessions View
    
    private var sessionsView: some View {
        VStack(spacing: 16) {
            // Header with revoke all button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Where You're Logged In")
                        .font(AMENFont.bold(18))
                    Text("\(securityService.activeSessions.count) active sessions")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if securityService.activeSessions.count > 1 {
                    Button {
                        showRevokeAllConfirmation = true
                    } label: {
                        Text("Log Out All")
                            .font(AMENFont.medium(13))
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Sessions list
            if securityService.activeSessions.isEmpty {
                emptyStateView(
                    icon: "lock.shield",
                    title: "No Active Sessions",
                    subtitle: "Your session history will appear here"
                )
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(securityService.activeSessions) { session in
                        sessionCard(session)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func sessionCard(_ session: ActiveSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Device icon
                ZStack {
                    Circle()
                        .fill(session.current ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: deviceIcon(for: session.deviceInfo.platform))
                        .font(.systemScaled(20))
                        .foregroundStyle(session.current ? .green : .primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(session.displayName)
                            .font(AMENFont.semiBold(15))
                        
                        if session.current {
                            Text("(Current)")
                                .font(AMENFont.medium(12))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    Text(session.deviceInfo.platform + " • " + session.deviceInfo.osVersion)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !session.current {
                    Button {
                        sessionToRevoke = session
                        showRevokeConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(20))
                            .foregroundStyle(.gray)
                    }
                }
            }
            
            Divider()
            
            // Session details
            VStack(alignment: .leading, spacing: 6) {
                infoRow(icon: "location.fill", text: session.location?.city ?? "Unknown location")
                infoRow(icon: "clock.fill", text: "Last active \(session.lastActiveAt.formatted(.relative(presentation: .named)))")
                if let city = session.location?.city, let country = session.location?.country {
                    infoRow(icon: "globe", text: "\(city), \(country)")
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Login History View
    
    private var loginHistoryView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Login History")
                        .font(AMENFont.bold(18))
                    Text("Last 20 login attempts")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            if securityService.loginHistory.isEmpty {
                emptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No Login History",
                    subtitle: "Your login attempts will appear here"
                )
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(securityService.loginHistory) { record in
                        loginRecordCard(record)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func loginRecordCard(_ record: LoginRecord) -> some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(record.success ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.systemScaled(18))
                    .foregroundStyle(record.success ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(record.success ? "Successful Login" : "Failed Login")
                    .font(AMENFont.semiBold(14))
                    .foregroundStyle(record.success ? Color.primary : Color.red)
                
                Text(record.deviceInfo.deviceName + " • " + record.deviceInfo.platform)
                    .font(AMENFont.regular(12))
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 8) {
                    if let city = record.location?.city {
                        Label(city, systemImage: "location.fill")
                            .font(AMENFont.regular(11))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(record.timestamp.formatted(.relative(presentation: .named)))
                        .font(AMENFont.regular(11))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Risk indicator
            if record.riskScore > 0.5 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.systemScaled(16))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Events View
    
    private var eventsView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Security Activity")
                        .font(AMENFont.bold(18))
                    Text("Recent account activity")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            if securityService.securityEvents.isEmpty {
                emptyStateView(
                    icon: "shield.checkered",
                    title: "No Security Events",
                    subtitle: "Important account activity will appear here"
                )
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(securityService.securityEvents) { event in
                        eventCard(event)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    private func eventCard(_ event: SecurityEvent) -> some View {
        HStack(spacing: 12) {
            // Event icon
            Image(systemName: eventIcon(for: event.eventType))
                .font(.systemScaled(18))
                .foregroundStyle(eventColor(for: event.eventType))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.displayTitle)
                    .font(AMENFont.semiBold(14))
                
                if let device = event.deviceInfo {
                    Text(device.deviceName)
                        .font(AMENFont.regular(12))
                        .foregroundStyle(.secondary)
                }
                
                Text(event.timestamp.formatted(.relative(presentation: .named)))
                    .font(AMENFont.regular(11))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Helper Views
    
    private func emptyStateView(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(48))
                .foregroundStyle(.gray.opacity(0.5))
            
            Text(title)
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.secondary)
            
            Text(subtitle)
                .font(AMENFont.regular(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.systemScaled(11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            
            Text(text)
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Helper Functions
    
    private func deviceIcon(for platform: String) -> String {
        switch platform.lowercased() {
        case "ios": return "iphone"
        case "android": return "phone.fill"
        case "web": return "desktopcomputer"
        default: return "laptopcomputer"
        }
    }
    
    private func eventIcon(for type: SecurityEventType) -> String {
        switch type {
        case .loginSuccess, .loginFailure: return "arrow.right.circle.fill"
        case .passwordChanged, .passwordResetCompleted: return "key.fill"
        case .emailChangeCompleted, .phoneChangeCompleted: return "envelope.fill"
        case .mfaEnabled, .mfaDisabled: return "lock.shield.fill"
        case .sessionRevoked, .allSessionsRevoked: return "arrow.left.circle.fill"
        case .accountDeactivated: return "pause.circle.fill"
        case .accountReactivated: return "play.circle.fill"
        case .suspiciousActivityDetected: return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }
    
    private func eventColor(for type: SecurityEventType) -> Color {
        switch type {
        case .loginSuccess, .accountReactivated, .mfaEnabled: return .green
        case .loginFailure, .accountDeactivated, .mfaDisabled: return .orange
        case .suspiciousActivityDetected: return .red
        default: return .blue
        }
    }
}

#Preview {
    SecurityCenterView()
}
