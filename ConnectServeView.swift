// ConnectServeView.swift
// AMENAPP
//
// Volunteer opportunities within the faith community.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct ServeOpportunity: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var description: String = ""
    var organizerName: String = ""
    var organizerUID: String = ""
    var church: String = ""
    var category: String = "General"
    var location: String = ""
    var isRemote: Bool = false
    var startDate: Date = Date()
    var spotsAvailable: Int = 0
    var signedUpUIDs: [String] = []
    var imageURL: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
}

// MARK: - View

struct ConnectServeView: View {
    @State private var opportunities: [ServeOpportunity] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var appeared = false
    @State private var selectedCategory: String? = nil

    private let categories = ["General", "Food Bank", "Youth", "Outreach", "Worship", "Tech", "Missions"]
    private let accentGreen = Color(red: 0.18, green: 0.62, blue: 0.36)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader
                categoryPills.padding(.top, 12)
                Divider().opacity(0.3).padding(.horizontal, 20).padding(.top, 8)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if filteredOpportunities.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredOpportunities) { opp in
                            serveCard(opp)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                Color.clear.frame(height: 100)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateServeSheet { newOpp in
                opportunities.insert(newOpp, at: 0)
            }
        }
        .task { await loadOpportunities() }
    }

    private var filteredOpportunities: [ServeOpportunity] {
        guard let cat = selectedCategory else { return opportunities }
        return opportunities.filter { $0.category == cat }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.45, blue: 0.25),
                    Color(red: 0.18, green: 0.62, blue: 0.36),
                    Color(red: 0.08, green: 0.35, blue: 0.20)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Color.white.opacity(0.06)).frame(width: 110).offset(x: -25, y: 25)

            VStack(alignment: .leading, spacing: 6) {
                Text("SERVE")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Serve Your Community")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                Text("Find volunteer opportunities and make an impact.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                Button { showCreate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Post Opportunity")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(accentGreen)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .padding(.top, 56)
        }
        .frame(minHeight: 200)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { appeared = true } }
    }

    // MARK: - Category Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.25)) { selectedCategory = nil }
                } label: {
                    Text("All")
                        .font(.system(size: 13, weight: selectedCategory == nil ? .bold : .regular))
                        .foregroundStyle(selectedCategory == nil ? .white : .secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(selectedCategory == nil ? accentGreen : Color(.secondarySystemBackground)))
                }

                ForEach(categories, id: \.self) { cat in
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    } label: {
                        Text(cat)
                            .font(.system(size: 13, weight: selectedCategory == cat ? .bold : .regular))
                            .foregroundStyle(selectedCategory == cat ? .white : .secondary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(selectedCategory == cat ? accentGreen : Color(.secondarySystemBackground)))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Serve Card

    private func serveCard(_ opp: ServeOpportunity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(opp.category.uppercased())
                    .font(.system(size: 10, weight: .bold)).kerning(1)
                    .foregroundStyle(accentGreen)
                Spacer()
                if opp.spotsAvailable > 0 {
                    Text("\(opp.spotsAvailable) spots left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Text(opp.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)

            Text(opp.description)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 12) {
                if !opp.church.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2").font(.system(size: 11))
                        Text(opp.church).font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                if !opp.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: opp.isRemote ? "wifi" : "mappin").font(.system(size: 11))
                        Text(opp.location).font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Button {
                signUp(for: opp)
            } label: {
                Text("Sign Up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Capsule().fill(accentGreen))
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
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No opportunities yet")
                .font(.system(size: 17, weight: .bold))
            Text("Be the first to post a volunteer opportunity!")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Data

    private func loadOpportunities() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("serveOpportunities")
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()

            opportunities = snap.documents.compactMap {
                try? Firestore.Decoder().decode(ServeOpportunity.self, from: $0.data())
            }
        } catch {
            dlog("ConnectServeView: Failed to load — \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func signUp(for opp: ServeOpportunity) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            let db = Firestore.firestore()
            try? await db.collection("serveOpportunities").document(opp.id).updateData([
                "signedUpUIDs": FieldValue.arrayUnion([uid]),
                "spotsAvailable": FieldValue.increment(Int64(-1))
            ])
        }
    }
}

// MARK: - Create Sheet

struct CreateServeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (ServeOpportunity) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var category = "General"
    @State private var church = ""
    @State private var location = ""
    @State private var isRemote = false
    @State private var spots = ""
    @State private var isSaving = false

    private let categories = ["General", "Food Bank", "Youth", "Outreach", "Worship", "Tech", "Missions"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                }
                Section("Location") {
                    TextField("Church or Organization", text: $church)
                    Toggle("Remote / Online", isOn: $isRemote)
                    if !isRemote {
                        TextField("Location", text: $location)
                    }
                }
                Section("Capacity") {
                    TextField("Available Spots", text: $spots)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Post Opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { save() }
                        .disabled(title.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isSaving = true
        let opp = ServeOpportunity(
            title: title,
            description: description,
            organizerUID: uid,
            church: church,
            category: category,
            location: isRemote ? "Remote" : location,
            isRemote: isRemote,
            spotsAvailable: Int(spots) ?? 0
        )
        Task {
            let db = Firestore.firestore()
            let encoded = try? Firestore.Encoder().encode(opp)
            if let encoded {
                try? await db.collection("serveOpportunities").document(opp.id).setData(encoded)
            }
            await MainActor.run {
                onCreate(opp)
                dismiss()
            }
        }
    }
}
