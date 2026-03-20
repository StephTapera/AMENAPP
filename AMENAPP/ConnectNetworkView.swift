// ConnectNetworkView.swift
// AMENAPP
//
// Browse and discover faith community members — search by name, church, interests.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ConnectNetworkView: View {
    @State private var searchText = ""
    @State private var people: [NetworkPerson] = []
    @State private var isLoading = true
    @State private var appeared = false

    private let accentColor = Color(red: 0.15, green: 0.45, blue: 0.82)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    TextField("Search people...", text: $searchText)
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

                // People list
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if filteredPeople.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPeople) { person in
                            NavigationLink(destination: UserProfileView(userId: person.uid)) {
                                personRow(person)
                            }
                            Divider().opacity(0.2).padding(.leading, 72)
                        }
                    }
                    .padding(.top, 8)
                }

                Color.clear.frame(height: 100)
            }
        }
        .task { await loadPeople() }
    }

    private var filteredPeople: [NetworkPerson] {
        guard !searchText.isEmpty else { return people }
        let query = searchText.lowercased()
        return people.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.church.lowercased().contains(query) ||
            $0.bio.lowercased().contains(query)
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.30, blue: 0.65),
                    Color(red: 0.18, green: 0.45, blue: 0.80),
                    Color(red: 0.08, green: 0.22, blue: 0.50)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Color.white.opacity(0.05)).frame(width: 100).offset(x: -20, y: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("NETWORK")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Faith Community")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                Text("Connect with believers near you and around the world.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .frame(minHeight: 170)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    // MARK: - Person Row

    private func personRow(_ person: NetworkPerson) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: person.photoURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Circle().fill(accentColor.opacity(0.15))
                        .overlay(
                            Text(String(person.displayName.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(accentColor)
                        )
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if !person.church.isEmpty {
                    Text(person.church)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !person.bio.isEmpty {
                    Text(person.bio)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No people found")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
            Text("Try a different search or check back later.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private func loadPeople() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("users")
                .limit(to: 50)
                .getDocuments()

            people = snap.documents.compactMap { doc -> NetworkPerson? in
                let data = doc.data()
                let docUID = doc.documentID
                guard docUID != uid else { return nil }
                return NetworkPerson(
                    uid: docUID,
                    displayName: data["displayName"] as? String ?? data["username"] as? String ?? "User",
                    photoURL: data["profileImageUrl"] as? String ?? data["photoURL"] as? String ?? "",
                    church: data["church"] as? String ?? "",
                    bio: data["bio"] as? String ?? ""
                )
            }
        } catch {
            dlog("ConnectNetworkView: Failed to load people — \(error.localizedDescription)")
        }
        isLoading = false
    }
}

private struct NetworkPerson: Identifiable {
    let uid: String
    var id: String { uid }
    let displayName: String
    let photoURL: String
    let church: String
    let bio: String
}
