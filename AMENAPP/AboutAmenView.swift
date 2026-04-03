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
            VStack(spacing: 0) {

                // MARK: App Identity Hero
                VStack(spacing: 16) {
                    Image(systemName: "hands.sparkles.fill")
                        .font(.systemScaled(80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)

                    Text("AMEN")
                        .font(AMENFont.bold(36))

                    Text("Version \(appVersion) (Build \(buildNumber))")
                        .font(AMENFont.regular(14))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)

                // MARK: Mission Statement Section
                Text("OUR MISSION")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        Text("Our Mission")
                            .font(AMENFont.bold(20))

                        Text("AMEN is a faith-based social platform designed to connect believers, share testimonies, support one another through prayer, and grow together in faith.")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // MARK: What We Offer Section
                Text("WHAT WE OFFER")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    let features: [(String, String, String)] = [
                        ("person.2.fill", "Community", "Connect with believers worldwide"),
                        ("hands.and.sparkles.fill", "Prayer", "Share and support prayer requests"),
                        ("doc.text.fill", "Testimonies", "Share your faith journey"),
                        ("book.fill", "Bible Study", "Grow together in God's Word"),
                        ("heart.fill", "Support", "Encourage and be encouraged")
                    ]

                    ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                        HStack(spacing: 16) {
                            Image(systemName: feature.0)
                                .font(.systemScaled(24))
                                .foregroundStyle(.blue)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.1)
                                    .font(AMENFont.semiBold(16))

                                Text(feature.2)
                                    .font(AMENFont.regular(14))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < features.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // MARK: Our Values Section
                Text("OUR VALUES")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ValueCardGlass(
                            icon: "cross.fill",
                            title: "Faith-Centered",
                            description: "Christ is at the heart of everything we do"
                        )
                        ValueCardGlass(
                            icon: "shield.fill",
                            title: "Safe & Supportive",
                            description: "A welcoming space for all believers"
                        )
                    }
                    HStack(spacing: 12) {
                        ValueCardGlass(
                            icon: "lock.fill",
                            title: "Privacy Focused",
                            description: "Your data and privacy are protected"
                        )
                        ValueCardGlass(
                            icon: "sparkles",
                            title: "Authentic",
                            description: "Real stories, real faith, real connections"
                        )
                    }
                }
                .padding(.horizontal, 16)

                // MARK: Links Section
                Text("LINKS")
                    .font(AMENFont.bold(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    Link(destination: URL(string: "https://amenapp.com")!) {
                        HStack {
                            Image(systemName: "globe")
                                .font(.systemScaled(16))
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            Text("Visit Our Website")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider().padding(.leading, 16)

                    Link(destination: URL(string: "https://amenapp.com/privacy")!) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.green)
                                .frame(width: 24)
                            Text("Privacy Policy")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider().padding(.leading, 16)

                    Link(destination: URL(string: "https://amenapp.com/terms")!) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            Text("Terms of Service")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider().padding(.leading, 16)

                    Button {
                        showCredits = true
                    } label: {
                        HStack {
                            Image(systemName: "person.3.fill")
                                .font(.systemScaled(16))
                                .foregroundStyle(.purple)
                                .frame(width: 24)
                            Text("Credits")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider().padding(.leading, 16)

                    Button {
                        showLicenses = true
                    } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.systemScaled(16))
                                .foregroundStyle(.gray)
                                .frame(width: 24)
                            Text("Open Source Licenses")
                                .font(AMENFont.semiBold(16))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.systemScaled(12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .padding(.horizontal, 16)

                // Copyright
                VStack(spacing: 8) {
                    Text("© 2026 AMEN App")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)

                    Text("Made with ❤️ for the Body of Christ")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                        .italic()
                }
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

// MARK: - Value Card (Glass variant)

private struct ValueCardGlass: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(title)
                .font(AMENFont.bold(15))
                .multilineTextAlignment(.center)

            Text(description)
                .font(AMENFont.regular(13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

// MARK: - Feature Row (kept for external use)

struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.systemScaled(24))
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AMENFont.semiBold(16))

                Text(description)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Value Card (kept for external use)

struct ValueCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(title)
                .font(AMENFont.bold(17))

            Text(description)
                .font(AMENFont.regular(14))
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

// MARK: - Link Button (kept for external use)

struct LinkButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.systemScaled(16))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.systemScaled(12, weight: .semibold))
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
                VStack(spacing: 0) {

                    Text("DEVELOPMENT")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        CreditRowGlass(role: "Lead Developer", name: "Steph Tapera")
                        Divider().padding(.leading, 16)
                        CreditRowGlass(role: "UI/UX Design", name: "Steph Tapera")
                        Divider().padding(.leading, 16)
                        CreditRowGlass(role: "Backend Development", name: "Firebase Team")
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("SPECIAL THANKS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Text("To the entire AMEN community for your faith, feedback, and support")
                            .font(AMENFont.regular(15))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("BUILT WITH")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        TechnologyRowGlass(name: "SwiftUI", description: "iOS Framework")
                        Divider().padding(.leading, 16)
                        TechnologyRowGlass(name: "Firebase", description: "Backend Services")
                        Divider().padding(.leading, 16)
                        TechnologyRowGlass(name: "CloudKit", description: "Data Sync")
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
                }
            }
        }
    }
}

private struct CreditRowGlass: View {
    let role: String
    let name: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(role)
                    .font(AMENFont.semiBold(15))
                Text(name)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct TechnologyRowGlass: View {
    let name: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(AMENFont.semiBold(15))
                Text(description)
                    .font(AMENFont.regular(14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - kept for external use (unchanged struct names)

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
                .font(AMENFont.bold(18))
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
                    .font(AMENFont.semiBold(15))
                Text(name)
                    .font(AMENFont.regular(14))
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
                    .font(AMENFont.semiBold(15))
                Text(description)
                    .font(AMENFont.regular(14))
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
            ScrollView {
                VStack(spacing: 0) {

                    Text("OPEN SOURCE LIBRARIES")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        if let url = URL(string: "https://github.com/firebase/firebase-ios-sdk") {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Firebase iOS SDK")
                                            .font(AMENFont.semiBold(15))
                                            .foregroundStyle(.primary)

                                        Text("Apache License 2.0")
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.systemScaled(12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Divider().padding(.leading, 16)

                        if let url = URL(string: "https://developer.apple.com") {
                            Link(destination: url) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("SwiftUI")
                                            .font(AMENFont.semiBold(15))
                                            .foregroundStyle(.primary)

                                        Text("Apple Software License")
                                            .font(AMENFont.regular(13))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.systemScaled(12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Text("ACKNOWLEDGMENTS")
                        .font(AMENFont.bold(11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)

                    VStack(spacing: 0) {
                        Text("AMEN uses open source software. We are grateful to the developers who contribute to these projects.")
                            .font(AMENFont.regular(14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                    .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Licenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AMENFont.semiBold(16))
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
        if let parsedURL = URL(string: url) {
            Link(destination: parsedURL) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(AMENFont.semiBold(15))
                        .foregroundStyle(.primary)

                    Text(license)
                        .font(AMENFont.regular(13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutAmenViewAlt()
    }
}
