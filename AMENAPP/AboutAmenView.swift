//
//  AboutAmenView.swift
//  AMENAPP
//
//  Created by Steph on 1/22/26.
//
//  NOTE: This file is being replaced by the AboutAmenView implementation in ProfileView.swift
//  This version can be deleted or kept as an alternative simpler version

import SwiftUI

// Renamed to avoid conflict with ProfileView.swift version
struct AboutAmenViewAlt: View {
    @Environment(\.dismiss) var dismiss
    @State private var showCredits = false
    @State private var showLicenses = false
    
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // App Logo and Name
                VStack(spacing: 16) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)
                    
                    Text("AMEN")
                        .font(.custom("OpenSans-Bold", size: 36))
                    
                    Text("Version \(appVersion) (Build \(buildNumber))")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                }
                
                // Mission Statement
                VStack(spacing: 12) {
                    Text("Our Mission")
                        .font(.custom("OpenSans-Bold", size: 20))
                    
                    Text("AMEN is a faith-based social platform designed to connect believers, share testimonies, support one another through prayer, and grow together in faith.")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineSpacing(4)
                }
                
                // Features
                VStack(spacing: 16) {
                    Text("What We Offer")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .padding(.bottom, 8)
                    
                    AboutFeatureRow(
                        icon: "person.2.fill",
                        title: "Community",
                        description: "Connect with believers worldwide"
                    )
                    
                    AboutFeatureRow(
                        icon: "hands.and.sparkles.fill",
                        title: "Prayer",
                        description: "Share and support prayer requests"
                    )
                    
                    AboutFeatureRow(
                        icon: "doc.text.fill",
                        title: "Testimonies",
                        description: "Share your faith journey"
                    )
                    
                    AboutFeatureRow(
                        icon: "book.fill",
                        title: "Bible Study",
                        description: "Grow together in God's Word"
                    )
                    
                    AboutFeatureRow(
                        icon: "heart.fill",
                        title: "Support",
                        description: "Encourage and be encouraged"
                    )
                }
                .padding(.horizontal)
                
                // Values
                VStack(spacing: 16) {
                    Text("Our Values")
                        .font(.custom("OpenSans-Bold", size: 20))
                        .padding(.bottom, 8)
                    
                    ValueCard(
                        icon: "cross.fill",
                        title: "Faith-Centered",
                        description: "Christ is at the heart of everything we do"
                    )
                    
                    ValueCard(
                        icon: "shield.fill",
                        title: "Safe & Supportive",
                        description: "A welcoming space for all believers"
                    )
                    
                    ValueCard(
                        icon: "lock.fill",
                        title: "Privacy Focused",
                        description: "Your data and privacy are protected"
                    )
                    
                    ValueCard(
                        icon: "sparkles",
                        title: "Authentic",
                        description: "Real stories, real faith, real connections"
                    )
                }
                .padding(.horizontal)
                
                // Links Section
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://amenapp.com")!) {
                        LinkButton(icon: "globe", title: "Visit Our Website", color: .blue)
                    }
                    
                    Link(destination: URL(string: "https://amenapp.com/privacy")!) {
                        LinkButton(icon: "hand.raised.fill", title: "Privacy Policy", color: .green)
                    }
                    
                    Link(destination: URL(string: "https://amenapp.com/terms")!) {
                        LinkButton(icon: "doc.text.fill", title: "Terms of Service", color: .orange)
                    }
                    
                    Button {
                        showCredits = true
                    } label: {
                        LinkButton(icon: "person.3.fill", title: "Credits", color: .purple)
                    }
                    
                    Button {
                        showLicenses = true
                    } label: {
                        LinkButton(icon: "list.bullet.rectangle", title: "Open Source Licenses", color: .gray)
                    }
                }
                .padding(.horizontal)
                
                // Copyright
                VStack(spacing: 8) {
                    Text("© 2026 AMEN App")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text("Made with ❤️ for the Body of Christ")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("About AMEN")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCredits) {
            CreditsView()
        }
        .sheet(isPresented: $showLicenses) {
            LicensesView()
        }
    }
}

// MARK: - Feature Row

struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("OpenSans-SemiBold", size: 16))
                
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Value Card

struct ValueCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(title)
                .font(.custom("OpenSans-Bold", size: 17))
            
            Text(description)
                .font(.custom("OpenSans-Regular", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Link Button

struct LinkButton: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 24)
            
            Text(title)
                .font(.custom("OpenSans-SemiBold", size: 16))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Credits View

struct CreditsView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Development Team
                    CreditSection(title: "Development") {
                        CreditRow(role: "Lead Developer", name: "Steph Tapera")
                        CreditRow(role: "UI/UX Design", name: "Steph Tapera")
                        CreditRow(role: "Backend Development", name: "Firebase Team")
                    }
                    
                    // Special Thanks
                    CreditSection(title: "Special Thanks") {
                        Text("To the entire AMEN community for your faith, feedback, and support")
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    
                    // Technologies Used
                    CreditSection(title: "Built With") {
                        TechnologyRow(name: "SwiftUI", description: "iOS Framework")
                        TechnologyRow(name: "Firebase", description: "Backend Services")
                        TechnologyRow(name: "CloudKit", description: "Data Sync")
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Credits")
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

struct CreditSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("OpenSans-Bold", size: 18))
                .padding(.horizontal)
            
            content
        }
    }
}

struct CreditRow: View {
    let role: String
    let name: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(role)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Text(name)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct TechnologyRow: View {
    let name: String
    let description: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                Text(description)
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - Licenses View

struct LicensesView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LicenseRow(
                        name: "Firebase iOS SDK",
                        license: "Apache License 2.0",
                        url: "https://github.com/firebase/firebase-ios-sdk"
                    )
                    
                    LicenseRow(
                        name: "SwiftUI",
                        license: "Apple Software License",
                        url: "https://developer.apple.com"
                    )
                } header: {
                    Text("OPEN SOURCE LIBRARIES")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
                
                Section {
                    Text("AMEN uses open source software. We are grateful to the developers who contribute to these projects.")
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                } header: {
                    Text("ACKNOWLEDGMENTS")
                        .font(.custom("OpenSans-Bold", size: 12))
                }
            }
            .navigationTitle("Licenses")
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

struct LicenseRow: View {
    let name: String
    let license: String
    let url: String
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.custom("OpenSans-SemiBold", size: 15))
                    .foregroundStyle(.primary)
                
                Text(license)
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutAmenView()
    }
}
