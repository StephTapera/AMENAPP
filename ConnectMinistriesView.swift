// ConnectMinistriesView.swift
// AMENAPP
//
// Browse and join ministry groups within the AMEN community.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct MinistryGroup: Identifiable, Codable {
    var id: String = UUID().uuidString
    var name: String = ""
    var description: String = ""
    var category: String = "General"
    var leaderName: String = ""
    var leaderUID: String = ""
    var church: String = ""
    var memberCount: Int = 0
    var memberUIDs: [String] = []
    var imageURL: String = ""
    var meetingSchedule: String = ""
    var isOpen: Bool = true
    var tags: [String] = []
    var createdAt: Date = Date()
}

// MARK: - View

struct ConnectMinistriesView: View {
    @State private var ministries: [MinistryGroup] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var appeared = false

    private let accentOrange = Color(red: 0.90, green: 0.47, blue: 0.10)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    TextField("Search ministries...", text: $searchText)
                        .font(.system(size: 15))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Divider().opacity(0.3).padding(.horizontal, 20).padding(.top, 12)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if filteredMinistries.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredMinistries) { ministry in
                            ministryCard(ministry)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                Color.clear.frame(height: 100)
            }
        }
        .task { await loadMinistries() }
    }

    private var filteredMinistries: [MinistryGroup] {
        guard !searchText.isEmpty else { return ministries }
        let q = searchText.lowercased()
        return ministries.filter {
            $0.name.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.church.lowercased().contains(q)
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.65, green: 0.30, blue: 0.05),
                    Color(red: 0.90, green: 0.47, blue: 0.10),
                    Color(red: 0.55, green: 0.25, blue: 0.05)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Color.white.opacity(0.06)).frame(width: 100).offset(x: -20, y: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("MINISTRIES")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Ministry Groups")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                Text("Find your place in the body of Christ.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .frame(minHeight: 170)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
    }

    // MARK: - Ministry Card

    private func ministryCard(_ ministry: MinistryGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(ministry.category.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(1)
                    .foregroundStyle(accentOrange)
                Spacer()
                if ministry.isOpen {
                    Text("Open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                }
            }

            Text(ministry.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            Text(ministry.description)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill").font(.system(size: 11))
                    Text("\(ministry.memberCount) members").font(.system(size: 12))
                }
                .foregroundStyle(.secondary)

                if !ministry.church.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2").font(.system(size: 11))
                        Text(ministry.church).font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if !ministry.meetingSchedule.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 11))
                    Text(ministry.meetingSchedule).font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
            }

            Button {
                joinMinistry(ministry)
            } label: {
                Text("Join Group")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Capsule().fill(accentOrange))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No ministries yet")
                .font(.system(size: 17, weight: .bold))
            Text("Ministry groups will appear here as churches create them.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Data

    private func loadMinistries() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("ministries")
                .order(by: "memberCount", descending: true)
                .limit(to: 30)
                .getDocuments()

            ministries = snap.documents.compactMap {
                try? Firestore.Decoder().decode(MinistryGroup.self, from: $0.data())
            }
        } catch {
            dlog("ConnectMinistriesView: Failed to load — \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func joinMinistry(_ ministry: MinistryGroup) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let db = Firestore.firestore()
            try? await db.collection("ministries").document(ministry.id).updateData([
                "memberUIDs": FieldValue.arrayUnion([uid]),
                "memberCount": FieldValue.increment(Int64(1))
            ])
        }
    }
}
