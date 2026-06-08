// ChurchCommunityProfileView.swift
// AMENAPP — FindChurchOS
// Full church profile tying together all community OS features.

import SwiftUI
import MapKit

// MARK: - Church Profile Model

struct ChurchCommunityProfile: Identifiable {
    let id: String
    var name: String
    var denomination: String?
    var tagline: String
    var address: String
    var coordinate: CLLocationCoordinate2D
    var serviceTimes: [ServiceTime]
    var ministries: [String]
    var leadPastorName: String
    var memberCount: Int
    var activeSpaceCount: Int
    var weeklyEventCount: Int
    var hasLivestream: Bool
    var websiteURL: String?

    struct ServiceTime: Identifiable {
        let id = UUID()
        var day: String
        var time: String
        var name: String
    }

    static let preview = ChurchCommunityProfile(
        id: "church-1",
        name: "Grace Community Church",
        denomination: "Non-denominational",
        tagline: "A place to belong, grow, and serve.",
        address: "123 Faith Ave, Nashville, TN 37201",
        coordinate: CLLocationCoordinate2D(latitude: 36.1627, longitude: -86.7816),
        serviceTimes: [
            ServiceTime(day: "Sunday", time: "9:00 AM", name: "Traditional Service"),
            ServiceTime(day: "Sunday", time: "11:00 AM", name: "Contemporary Service"),
            ServiceTime(day: "Wednesday", time: "7:00 PM", name: "Midweek Bible Study")
        ],
        ministries: ["Youth Ministry", "Women's Group", "Men's Breakfast", "Community Outreach", "Worship Team", "Children's Church"],
        leadPastorName: "Pastor James Williams",
        memberCount: 842,
        activeSpaceCount: 14,
        weeklyEventCount: 6,
        hasLivestream: true,
        websiteURL: nil
    )
}

// MARK: - Profile View

struct ChurchCommunityProfileView: View {
    let church: ChurchCommunityProfile
    let currentRole: SpaceMemberRole

    @State private var selectedSection: ProfileSection = .overview
    @State private var showJoinFlow = false
    @State private var position: MapCameraPosition

    enum ProfileSection: String, CaseIterable {
        case overview, spaces, events, notes, ministries, leadership

        var label: String {
            switch self {
            case .overview:    return "About"
            case .spaces:      return "Spaces"
            case .events:      return "Events"
            case .notes:       return "Notes"
            case .ministries:  return "Ministries"
            case .leadership:  return "Leadership"
            }
        }
    }

    init(church: ChurchCommunityProfile, currentRole: SpaceMemberRole) {
        self.church = church
        self.currentRole = currentRole
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: church.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header card
                headerCard

                // Section picker
                sectionPicker

                // Content
                switch selectedSection {
                case .overview:    overviewSection
                case .spaces:      spacesSection
                case .events:      eventsSection
                case .notes:       notesSection
                case .ministries:  ministriesSection
                case .leadership:  leadershipSection
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(church.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Join") { showJoinFlow = true }
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showJoinFlow) {
            ChurchJoinFlowView(church: church, onDismiss: { showJoinFlow = false })
                .presentationDetents([.large])
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Map thumbnail
            Map(position: $position) {
                Marker(church.name, coordinate: church.coordinate)
                    .tint(Color.accentColor)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(true)

            // Church info
            VStack(alignment: .leading, spacing: 6) {
                Text(church.name)
                    .font(.title2.weight(.bold))
                if let denom = church.denomination {
                    Text(denom)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                Text(church.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(church.address)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Stats row
            HStack(spacing: 0) {
                statCell(value: "\(church.memberCount)", label: "Members")
                Divider().frame(height: 32)
                statCell(value: "\(church.activeSpaceCount)", label: "Spaces")
                Divider().frame(height: 32)
                statCell(value: "\(church.weeklyEventCount)", label: "Events/wk")
                if church.hasLivestream {
                    Divider().frame(height: 32)
                    statCell(value: "Live", label: "Streaming")
                }
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(Color.accentColor)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // MARK: - Section Picker

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProfileSection.allCases, id: \.self) { section in
                    Button {
                        withAnimation(.spring(response: 0.28)) { selectedSection = section }
                    } label: {
                        Text(section.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .foregroundStyle(selectedSection == section ? .white : .primary)
                            .background(
                                selectedSection == section ? Color.accentColor : Color(.secondarySystemBackground),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Content Sections

    @ViewBuilder private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Service Times")
                .font(.headline)
                .padding(.horizontal, 16)
            ForEach(church.serviceTimes) { service in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name).font(.subheadline.weight(.semibold))
                        Text("\(service.day) · \(service.time)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        // TODO: implement add to calendar action
                    } label: {
                        Label("Add", systemImage: "calendar.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var spacesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(church.activeSpaceCount) Active Spaces")
                .font(.headline).padding(.horizontal, 16)
            Text("Join a Space to connect with others who share your season, ministry, or life stage.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            // Placeholder — real implementation loads from Firestore
            ForEach(0..<3, id: \.self) { i in
                SpacePlaceholderRow(index: i)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming Events").font(.headline).padding(.horizontal, 16)
            Text("Stay connected to what's happening in the church community.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared Notes").font(.headline).padding(.horizontal, 16)
            Text("Sermon notes and study guides shared by the church.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var ministriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ministries").font(.headline).padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(church.ministries, id: \.self) { ministry in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor).font(.caption)
                        Text(ministry).font(.caption).lineLimit(2)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var leadershipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leadership").font(.headline).padding(.horizontal, 16)
            HStack(spacing: 12) {
                Circle().fill(Color.accentColor.opacity(0.2)).frame(width: 52, height: 52)
                    .overlay(Image(systemName: "person.fill").foregroundStyle(Color.accentColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(church.leadPastorName).font(.subheadline.weight(.semibold))
                    Text("Lead Pastor").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }
}

// MARK: - Space Placeholder Row

private struct SpacePlaceholderRow: View {
    let index: Int
    private let names = ["Women's Morning Bible Study", "Youth & Young Adults", "Prayer Warriors Group"]
    private let counts = [23, 47, 18]

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(names[index]).font(.subheadline.weight(.semibold))
                Text("\(counts[index]) members").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                // TODO: implement join group action
            } label: {
                Text("Join")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Join Flow

struct ChurchJoinFlowView: View {
    let church: ChurchCommunityProfile
    let onDismiss: () -> Void

    private let steps = [
        "Join the main church Space",
        "Create your first sermon note",
        "Add a service time to your calendar",
        "RSVP to an upcoming event",
        "Connect with a mentor",
        "Join a small group"
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Welcome to \(church.name)!")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal)

                Text("Here's how to get connected:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 14) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.accentColor, in: Circle())
                        Text(step)
                            .font(.subheadline)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Text("Get Started")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Getting Connected")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onDismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ChurchCommunityProfileView(church: .preview, currentRole: .member)
    }
}
