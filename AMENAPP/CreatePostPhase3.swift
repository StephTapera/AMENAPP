//
//  CreatePostPhase3.swift
//  AMENAPP
//
//  Phase 3 Advanced Features:
//  - Image crop/edit
//  - Save as template
//  - Thread creation (1/n)
//

import SwiftUI
import PhotosUI

// MARK: - Phase 3: Image Crop Editor (Basic)

struct ImageCropEditor: View {
    @Binding var imageData: Data
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = lastScale * value
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    }
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                    }
                    
                    // Crop frame overlay
                    Rectangle()
                        .strokeBorder(.white, lineWidth: 2)
                        .frame(width: geometry.size.width - 40, height: geometry.size.width - 40)
                }
            }
            .navigationTitle("Crop Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // In a real implementation, crop the image here
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
    }
}

// MARK: - Phase 3: Save Template Sheet

struct SaveTemplateSheet: View {
    @Binding var templateName: String
    @Binding var postText: String
    let category: Post.PostCategory
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Save this post structure as a template for future use")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Name")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    TextField("e.g., Prayer Request for Healing", text: $templateName)
                        .font(.custom("OpenSans-Regular", size: 16))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .focused($isFocused)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Template Preview")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    ScrollView {
                        Text(postText.isEmpty ? "Your post content will appear here" : postText)
                            .font(.custom("OpenSans-Regular", size: 15))
                            .foregroundStyle(postText.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                    }
                    .frame(height: 150)
                }
                
                Spacer()
                
                Button {
                    onSave()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill")
                        Text("Save Template")
                            .fontWeight(.semibold)
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(templateName.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .disabled(templateName.isEmpty)
            }
            .navigationTitle("Save Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Phase 3: Thread Composer

struct ThreadComposerView: View {
    @Binding var threadPosts: [String]
    @Binding var currentIndex: Int
    @State private var showAddPostPrompt = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Thread navigation header
            HStack {
                Text("Thread \(currentIndex + 1) of \(threadPosts.count)")
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Previous button
                    Button {
                        if currentIndex > 0 {
                            currentIndex -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(currentIndex > 0 ? .blue : .gray.opacity(0.3))
                    }
                    .disabled(currentIndex == 0)
                    
                    // Next button
                    Button {
                        if currentIndex < threadPosts.count - 1 {
                            currentIndex += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(currentIndex < threadPosts.count - 1 ? .blue : .gray.opacity(0.3))
                    }
                    .disabled(currentIndex == threadPosts.count - 1)
                    
                    // Add post button
                    Button {
                        threadPosts.append("")
                        currentIndex = threadPosts.count - 1
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            Divider()
            
            // Thread posts list preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(threadPosts.indices, id: \.self) { index in
                        ThreadPostPreviewCard(
                            postNumber: index + 1,
                            text: threadPosts[index],
                            isActive: index == currentIndex,
                            onTap: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    currentIndex = index
                                }
                            },
                            onDelete: {
                                if threadPosts.count > 1 {
                                    threadPosts.remove(at: index)
                                    if currentIndex >= threadPosts.count {
                                        currentIndex = threadPosts.count - 1
                                    }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }
}

struct ThreadPostPreviewCard: View {
    let postNumber: Int
    let text: String
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(postNumber)")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(isActive ? .white : .primary)
                
                Spacer()
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isActive ? .white.opacity(0.7) : .secondary)
                }
            }
            
            Text(text.isEmpty ? "Tap to edit..." : String(text.prefix(60)) + (text.count > 60 ? "..." : ""))
                .font(.custom("OpenSans-Regular", size: 12))
                .foregroundStyle(isActive ? .white.opacity(0.9) : .secondary)
                .lineLimit(2)
                .frame(height: 36)
        }
        .padding(12)
        .frame(width: 140)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.blue : Color(.systemGray5))
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Post Template Model

struct PostTemplate: Codable, Identifiable {
    let id: String
    let name: String
    let content: String
    let category: String
    let createdAt: Date
    
    init(id: String = UUID().uuidString, name: String, content: String, category: Post.PostCategory, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.category = category.rawValue
        self.createdAt = createdAt
    }
}

// MARK: - Template Manager

@MainActor
class PostTemplateManager: ObservableObject {
    static let shared = PostTemplateManager()
    
    @Published var templates: [PostTemplate] = []
    
    private let userDefaults = UserDefaults.standard
    private let templatesKey = "saved_post_templates"
    
    private init() {
        loadTemplates()
    }
    
    func saveTemplate(_ template: PostTemplate) {
        templates.append(template)
        persist()
        dlog("📝 Template saved: \(template.name)")
    }
    
    func deleteTemplate(id: String) {
        templates.removeAll { $0.id == id }
        persist()
    }
    
    func getTemplates(for category: Post.PostCategory) -> [PostTemplate] {
        return templates.filter { $0.category == category.rawValue }
    }
    
    private func loadTemplates() {
        if let data = userDefaults.data(forKey: templatesKey),
           let decoded = try? JSONDecoder().decode([PostTemplate].self, from: data) {
            templates = decoded
            dlog("📝 Loaded \(templates.count) templates")
        }
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(templates) {
            userDefaults.set(encoded, forKey: templatesKey)
        }
    }
}

// MARK: - Template Picker Sheet

struct TemplatePickerSheet: View {
    let category: Post.PostCategory
    let onSelect: (PostTemplate) -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var templateManager = PostTemplateManager.shared
    
    var categoryTemplates: [PostTemplate] {
        templateManager.getTemplates(for: category)
    }
    
    var body: some View {
        NavigationView {
            Group {
                if categoryTemplates.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text("No templates yet")
                            .font(.custom("OpenSans-SemiBold", size: 18))
                        
                        Text("Create templates to reuse common post structures")
                            .font(.custom("OpenSans-Regular", size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(categoryTemplates) { template in
                            Button {
                                onSelect(template)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(template.name)
                                            .font(.custom("OpenSans-SemiBold", size: 15))
                                            .foregroundStyle(.primary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text(template.content)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                templateManager.deleteTemplate(id: categoryTemplates[index].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
