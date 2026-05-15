//
//  TestimonyCategoryDetailView.swift
//  AMENAPP
//
//  Created by Steph on 1/16/26.
//

import SwiftUI
import FirebaseFirestore

struct TestimonyCategoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let category: TestimonyCategory
    @State private var selectedFilter: CategoryFilter = .recent
    @State private var posts: [CategoryPost] = []
    @State private var isLoading = false

    enum CategoryFilter: String, CaseIterable {
        case recent = "Recent"
        case popular = "Popular"
        case inspiring = "Inspiring"
    }

    var categoryPosts: [CategoryPost] {
        switch selectedFilter {
        case .recent:
            return posts
        case .popular:
            return posts.sorted { ($0.likes ?? 0) > ($1.likes ?? 0) }
        case .inspiring:
            return posts.filter { ($0.likes ?? 0) >= 5 }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with Icon
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(category.backgroundColor)
                                .frame(width: 80, height: 80)

                            Image(systemName: category.icon)
                                .font(.systemScaled(40, weight: .semibold))
                                .foregroundStyle(category.color)
                        }

                        Text(category.title)
                            .font(.custom("OpenSans-Bold", size: 28))
                            .foregroundStyle(.primary)

                        Text(category.subtitle)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    // Filters - Center Aligned
                    HStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(CategoryFilter.allCases, id: \.self) { filter in
                                Button {
                                    withAnimation(Motion.adaptive(.spring(response: 0.3, dampingFraction: 0.7))) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                        .foregroundStyle(selectedFilter == filter ? .white : .primary)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(selectedFilter == filter ? category.color : Color.gray.opacity(0.1))
                                        )
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Posts
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else if categoryPosts.isEmpty {
                        ContentUnavailableView(
                            "No \(category.title) Testimonies",
                            systemImage: category.icon,
                            description: Text("Be the first to share a testimony in this category.")
                        )
                        .padding(.top, 32)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(categoryPosts) { post in
                                PostCard(
                                    authorName: post.authorName,
                                    timeAgo: post.timeAgo,
                                    content: post.content,
                                    category: .testimonies
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.systemScaled(28))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Share category
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.systemScaled(18))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .task { await loadPosts() }
        }
    }

    // MARK: - Data Loading

    private func loadPosts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snap = try await Firestore.firestore()
                .collection("posts")
                .whereField("type", isEqualTo: "testimony")
                .whereField("testimonyCategory", isEqualTo: category.title)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()

            posts = snap.documents.compactMap { doc -> CategoryPost? in
                let d = doc.data()
                guard let content = d["text"] as? String ?? d["content"] as? String else { return nil }
                let authorName = d["authorName"] as? String ?? "Anonymous"
                let likes = d["likes"] as? Int
                let ts = (d["timestamp"] as? Timestamp)?.dateValue()
                let timeAgo = ts.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? ""
                return CategoryPost(authorName: authorName, timeAgo: timeAgo, content: content, likes: likes)
            }
        } catch {
            dlog("⚠️ TestimonyCategoryDetailView loadPosts: \(error)")
        }
    }
}

// MARK: - Category Post Model

struct CategoryPost: Identifiable {
    let id = UUID()
    let authorName: String
    let timeAgo: String
    let content: String
    var likes: Int?
}

#Preview {
    TestimonyCategoryDetailView(category: .healing)
}
