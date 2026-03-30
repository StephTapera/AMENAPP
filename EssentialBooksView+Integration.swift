//
//  EssentialBooksView+Integration.swift
//  AMENAPP
//
//  Integration snippet for EssentialBooksView.swift
//  Replace the existing SmartBookCard and GridBookCard with these updated versions
//

import SwiftUI

// MARK: - Updated Book Cards with ViewModel Integration

struct SmartBookCard_WithViewModel: View {
    let book: Book
    @ObservedObject var viewModel: BooksViewModel
    @State private var showDetail = false
    
    var isSaved: Bool {
        viewModel.isBookSaved(book)
    }
    
    var body: some View {
        Button {
            showDetail = true
            Task {
                await viewModel.viewBook(book)
            }
        } label: {
            HStack(spacing: 16) {
                // Book cover
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: book.coverColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 120)
                    
                    Image(systemName: "book.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text("by \(book.author)")
                        .font(.custom("OpenSans-SemiBold", size: 13))
                        .foregroundStyle(.secondary)
                    
                    Text(book.description)
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        // Rating
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(systemName: index < book.rating ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                        Text(book.category)
                            .font(.custom("OpenSans-SemiBold", size: 11))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.1))
                            )
                    }
                }
                
                Spacer()
                
                Button {
                    Task {
                        await viewModel.toggleSaveBook(book)
                        let haptic = UIImpactFeedbackGenerator(style: .light)
                        haptic.impactOccurred()
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isSaved ? .blue : .secondary)
                        .symbolEffect(.bounce, value: isSaved)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            BookDetailView(book: book)
        }
    }
}

struct GridBookCard_WithViewModel: View {
    let book: Book
    @ObservedObject var viewModel: BooksViewModel
    @State private var showDetail = false
    
    var isSaved: Bool {
        viewModel.isBookSaved(book)
    }
    
    var body: some View {
        Button {
            showDetail = true
            Task {
                await viewModel.viewBook(book)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: book.coverColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .aspectRatio(0.67, contentMode: .fit)
                        
                        Image(systemName: "book.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    
                    Button {
                        Task {
                            await viewModel.toggleSaveBook(book)
                            let haptic = UIImpactFeedbackGenerator(style: .light)
                            haptic.impactOccurred()
                        }
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18))
                            .foregroundStyle(isSaved ? .blue : .white)
                            .symbolEffect(.bounce, value: isSaved)
                            .padding(8)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                            )
                    }
                    .padding(8)
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.title)
                        .font(.custom("OpenSans-Bold", size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    
                    Text(book.author)
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < book.rating ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showDetail) {
            BookDetailView(book: book)
        }
    }
}

// MARK: - Updated Book Detail View

struct BookDetailView_WithViewModel: View {
    @Environment(\.dismiss) var dismiss
    let book: Book
    @ObservedObject var viewModel: BooksViewModel
    
    var isSaved: Bool {
        viewModel.isBookSaved(book)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large book cover
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: book.coverColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 300)
                        
                        Image(systemName: "book.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .padding(.top, 32)
                    
                    VStack(spacing: 12) {
                        Text(book.title)
                            .font(.custom("OpenSans-Bold", size: 26))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                        
                        Text("by \(book.author)")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 16) {
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < book.rating ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.orange)
                                }
                            }
                            
                            Text(book.category)
                                .font(.custom("OpenSans-SemiBold", size: 14))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.blue.opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        if let purchaseURL = book.purchaseURL, let url = URL(string: purchaseURL) {
                            Link(destination: url) {
                                Text("Get Book")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black)
                                    )
                            }
                        } else {
                            Button {
                                // Show purchase options
                            } label: {
                                Text("Get Book")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.black)
                                    )
                            }
                        }
                        
                        Button {
                            Task {
                                await viewModel.toggleSaveBook(book)
                                let haptic = UIImpactFeedbackGenerator(style: .light)
                                haptic.impactOccurred()
                            }
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 18))
                                .foregroundStyle(isSaved ? .white : .primary)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSaved ? Color.blue : Color(.systemGray6))
                                )
                        }
                        .symbolEffect(.bounce, value: isSaved)
                        
                        ShareLink(item: book.title) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(.primary)
                                .frame(width: 50, height: 50)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemGray6))
                                )
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About This Book")
                            .font(.custom("OpenSans-Bold", size: 20))
                        
                        Text(book.description)
                            .font(.custom("OpenSans-Regular", size: 16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                        
                        // Stats
                        HStack(spacing: 24) {
                            VStack(spacing: 4) {
                                Text("\(book.savedCount)")
                                    .font(.custom("OpenSans-Bold", size: 20))
                                Text("Saved")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            
                            VStack(spacing: 4) {
                                Text("\(book.viewCount)")
                                    .font(.custom("OpenSans-Bold", size: 20))
                                Text("Views")
                                    .font(.custom("OpenSans-Regular", size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.viewBook(book)
            }
        }
    }
}

// MARK: - Usage in EssentialBooksView

/*
 In your EssentialBooksView, update the body's ScrollView section:
 
 if viewMode == .list {
     ForEach(filteredBooks) { book in
         SmartBookCard_WithViewModel(book: book, viewModel: viewModel)
     }
 } else {
     LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
         ForEach(filteredBooks) { book in
             GridBookCard_WithViewModel(book: book, viewModel: viewModel)
         }
     }
     .padding(.horizontal, 20)
 }
 
 Also add .onAppear modifier to the main VStack:
 
 .onAppear {
     Task {
         await viewModel.loadInitialData()
     }
 }
 
 And add a refresh control:
 
 .refreshable {
     await viewModel.loadInitialData()
 }
*/
