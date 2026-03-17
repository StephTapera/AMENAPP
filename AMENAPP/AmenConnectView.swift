//
//  AMENConnectView.swift
//  AMENAPP
//
//  AMEN Connect hub — jobs, networking, serve, mentorship, events.
//

import SwiftUI

enum AMENConnectTab: String, CaseIterable, Codable {
    case forYou = "For You"
    case jobs = "Jobs"
    case network = "Network"
    case serve = "Serve"
    case events = "Events"
    case ministries = "Ministries"
    case converse = "Conversations"
    case mentorship = "Mentorship"
    case marketplace = "Marketplace"
    case forum = "Forum"
    case prayer = "Prayer"
}

struct AMENConnectView: View {
    var initialTab: AMENConnectTab = .forYou

    @State private var selectedTab: AMENConnectTab = .forYou

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AMENConnectTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.25)) { selectedTab = tab }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? .white : .secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selectedTab == tab ? Color.blue : Color(.systemGray6))
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            // Content
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.opacity(0.5))
                        .padding(.top, 40)

                    Text("AMEN Connect")
                        .font(.system(size: 22, weight: .bold))

                    Text("Find jobs, serve opportunities, mentorship, and community connections — all within the AMEN network.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if selectedTab == .jobs {
                        NavigationLink(destination: JobSearchView()) {
                            connectCard(icon: "briefcase.fill", title: "Browse Jobs", color: .blue)
                        }
                    }

                    Spacer(minLength: 60)
                }
            }
        }
        .navigationTitle("AMEN Connect")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedTab = initialTab }
    }

    private func connectCard(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
        .padding(.horizontal, 16)
    }
}

struct AMENConnectEntryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
                Text("AMEN Connect")
                    .font(.system(size: 18, weight: .bold))
            }
            Text("Jobs, serve, mentor, and connect with the faith community")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemGray6)))
    }
}
