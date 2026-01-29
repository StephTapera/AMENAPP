//
//  TestimonyCategoryDetailView.swift
//  AMENAPP
//
//  Created by Steph on 1/16/26.
//

import SwiftUI

struct TestimonyCategoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let category: TestimonyCategory
    @State private var selectedFilter: CategoryFilter = .recent
    
    enum CategoryFilter: String, CaseIterable {
        case recent = "Recent"
        case popular = "Popular"
        case inspiring = "Inspiring"
    }
    
    var categoryPosts: [CategoryPost] {
        switch category.title {
        case "Healing":
            return healingPosts
        case "Career":
            return careerPosts
        case "Relationships":
            return relationshipPosts
        case "Financial":
            return financialPosts
        case "Spiritual Growth":
            return spiritualPosts
        case "Family":
            return familyPosts
        default:
            return []
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
                                .font(.system(size: 40, weight: .semibold))
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
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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
                            .font(.system(size: 28))
                            .foregroundStyle(.gray.opacity(0.3))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Share category
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
    
    // MARK: - Category Posts Data
    // Sample data removed - will be replaced with real data from Firebase
    
    private var healingPosts: [CategoryPost] { [] }
    private var careerPosts: [CategoryPost] { [] }
    private var relationshipPosts: [CategoryPost] { [] }
    private var financialPosts: [CategoryPost] { [] }
    private var spiritualPosts: [CategoryPost] { [] }
    private var familyPosts: [CategoryPost] { [] }
}

// MARK: - Category Post Model

struct CategoryPost: Identifiable {
    let id = UUID()
    let authorName: String
    let timeAgo: String
    let content: String
}

#Preview {
    TestimonyCategoryDetailView(category: .healing)
}
