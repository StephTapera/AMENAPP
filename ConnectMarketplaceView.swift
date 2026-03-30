// ConnectMarketplaceView.swift
// AMENAPP
//
// Faith-based marketplace — books, courses, art, and services from the community.

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Model

struct MarketplaceListing: Identifiable, Codable {
    var id: String = UUID().uuidString
    var title: String = ""
    var description: String = ""
    var price: Double = 0.0
    var isFree: Bool = false
    var category: String = "General"
    var sellerUID: String = ""
    var sellerName: String = ""
    var imageURL: String = ""
    var condition: String = "New"
    var location: String = ""
    var isShippable: Bool = true
    var tags: [String] = []
    var createdAt: Date = Date()
}

// MARK: - View

struct ConnectMarketplaceView: View {
    @State private var listings: [MarketplaceListing] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var appeared = false

    private let categories = ["Books", "Courses", "Art", "Music", "Services", "Clothing", "Other"]
    private let accentIndigo = Color(red: 0.38, green: 0.25, blue: 0.78)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader

                // Search
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    TextField("Search marketplace...", text: $searchText)
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

                categoryPills.padding(.top, 12)
                Divider().opacity(0.3).padding(.horizontal, 20).padding(.top, 8)

                if isLoading {
                    ProgressView().padding(.top, 40)
                } else if filteredListings.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredListings) { listing in
                            listingCard(listing)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }

                Color.clear.frame(height: 100)
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateMarketplaceSheet { newListing in
                listings.insert(newListing, at: 0)
            }
        }
        .task { await loadListings() }
    }

    private var filteredListings: [MarketplaceListing] {
        var result = listings
        if let cat = selectedCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        return result
    }

    // MARK: - Hero

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.15, blue: 0.55),
                    Color(red: 0.38, green: 0.25, blue: 0.78),
                    Color(red: 0.20, green: 0.12, blue: 0.45)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(Color.white.opacity(0.06)).frame(width: 100).offset(x: -20, y: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("MARKETPLACE")
                    .font(.system(size: 10, weight: .semibold)).kerning(3)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("Faith Marketplace")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                Text("Buy, sell, and share resources within the community.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))

                Button { showCreate = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("List an Item").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(accentIndigo)
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
                        .background(Capsule().fill(selectedCategory == nil ? accentIndigo : Color(.secondarySystemBackground)))
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
                            .background(Capsule().fill(selectedCategory == cat ? accentIndigo : Color(.secondarySystemBackground)))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Listing Card

    private func listingCard(_ listing: MarketplaceListing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            AsyncImage(url: URL(string: listing.imageURL)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Color(red: 0.38, green: 0.25, blue: 0.78).opacity(0.15)
                        .overlay(
                            Image(systemName: "bag.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(accentIndigo.opacity(0.3))
                        )
                }
            }
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(listing.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if listing.isFree {
                Text("Free")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Text("$\(String(format: "%.2f", listing.price))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accentIndigo)
            }

            Text(listing.sellerName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
                .padding(.top, 40)
            Text("No listings yet")
                .font(.system(size: 17, weight: .bold))
            Text("Be the first to list something on the marketplace!")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Data

    private func loadListings() async {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("marketplace")
                .order(by: "createdAt", descending: true)
                .limit(to: 30)
                .getDocuments()

            listings = snap.documents.compactMap {
                try? Firestore.Decoder().decode(MarketplaceListing.self, from: $0.data())
            }
        } catch {
            dlog("ConnectMarketplaceView: Failed to load — \(error.localizedDescription)")
        }
        isLoading = false
    }
}

// MARK: - Create Sheet

struct CreateMarketplaceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (MarketplaceListing) -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var price = ""
    @State private var isFree = false
    @State private var category = "Books"
    @State private var condition = "New"
    @State private var isSaving = false

    private let categories = ["Books", "Courses", "Art", "Music", "Services", "Clothing", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    Picker("Condition", selection: $condition) {
                        Text("New").tag("New")
                        Text("Like New").tag("Like New")
                        Text("Good").tag("Good")
                        Text("Used").tag("Used")
                    }
                }
                Section("Pricing") {
                    Toggle("Free", isOn: $isFree)
                    if !isFree {
                        TextField("Price", text: $price)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("List Item")
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
        guard let uid = Auth.auth().currentUser?.uid,
              let user = Auth.auth().currentUser else { return }
        isSaving = true
        let listing = MarketplaceListing(
            title: title,
            description: description,
            price: Double(price) ?? 0.0,
            isFree: isFree,
            category: category,
            sellerUID: uid,
            sellerName: user.displayName ?? "User",
            condition: condition
        )
        Task {
            let db = Firestore.firestore()
            let encoded = try? Firestore.Encoder().encode(listing)
            if let encoded {
                try? await db.collection("marketplace").document(listing.id).setData(encoded)
            }
            await MainActor.run {
                onCreate(listing)
                dismiss()
            }
        }
    }
}
