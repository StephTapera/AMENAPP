//
//  MemeGenerator.swift
//  AMENAPP
//
//  Built-in meme generator for messaging
//

import SwiftUI
import UIKit
import PhotosUI

// MARK: - Meme Template

struct MemeTemplate: Identifiable {
    let id = UUID()
    let name: String
    let imageName: String
    let topTextDefault: String
    let bottomTextDefault: String
    let category: MemeCategory
    
    static let faithMemes: [MemeTemplate] = [
        MemeTemplate(
            name: "Distracted Boyfriend",
            imageName: "meme_distracted",
            topTextDefault: "ME",
            bottomTextDefault: "BINGE WATCHING / BIBLE STUDY",
            category: .faith
        ),
        MemeTemplate(
            name: "Drake Hotline",
            imageName: "meme_drake",
            topTextDefault: "WORRYING",
            bottomTextDefault: "PRAYING",
            category: .faith
        ),
        MemeTemplate(
            name: "Two Buttons",
            imageName: "meme_buttons",
            topTextDefault: "READ BIBLE",
            bottomTextDefault: "SCROLL INSTAGRAM",
            category: .faith
        ),
        MemeTemplate(
            name: "Change My Mind",
            imageName: "meme_change_mind",
            topTextDefault: "PRAYER WORKS",
            bottomTextDefault: "CHANGE MY MIND",
            category: .faith
        ),
        MemeTemplate(
            name: "Is This...",
            imageName: "meme_butterfly",
            topTextDefault: "IS THIS",
            bottomTextDefault: "A SIGN FROM GOD?",
            category: .faith
        ),
    ]
}

enum MemeCategory: String, CaseIterable {
    case faith = "Faith"
    case funny = "Funny"
    case wholesome = "Wholesome"
    case custom = "Custom"
}

// MARK: - Meme Generator View

struct MemeGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplate: MemeTemplate?
    @State private var customImage: UIImage?
    @State private var topText = ""
    @State private var bottomText = ""
    @State private var textColor: Color = .white
    @State private var textOutlineColor: Color = .black
    @State private var fontSize: CGFloat = 40
    @State private var selectedItem: PhotosPickerItem?
    @State private var generatedMeme: UIImage?
    @State private var showShareSheet = false
    
    let onSend: (UIImage) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Image preview
                        memePreviewSection
                        
                        // Text inputs
                        textInputsSection
                        
                        // Customization
                        customizationSection
                        
                        // Template selector
                        if customImage == nil {
                            templateSelectorSection
                        }
                        
                        // Actions
                        actionButtonsSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Create Meme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let meme = generatedMeme {
                    ShareSheet(items: [meme])
                }
            }
        }
    }
    
    // MARK: - Preview Section
    
    private var memePreviewSection: some View {
        VStack {
            ZStack {
                // Background image
                if let customImage = customImage {
                    Image(uiImage: customImage)
                        .resizable()
                        .scaledToFit()
                } else if let template = selectedTemplate {
                    // Placeholder for template image
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Text(template.name)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        )
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.secondary)
                                Text("Select a template or upload an image")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        )
                }
                
                // Text overlays
                VStack {
                    if !topText.isEmpty {
                        memeText(topText)
                            .padding(.top, 20)
                    }
                    
                    Spacer()
                    
                    if !bottomText.isEmpty {
                        memeText(bottomText)
                            .padding(.bottom, 20)
                    }
                }
            }
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
    }
    
    private func memeText(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: fontSize, weight: .black))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .shadow(color: textOutlineColor, radius: 2, x: -2, y: -2)
            .shadow(color: textOutlineColor, radius: 2, x: 2, y: 2)
            .shadow(color: textOutlineColor, radius: 2, x: -2, y: 2)
            .shadow(color: textOutlineColor, radius: 2, x: 2, y: -2)
            .padding(.horizontal)
    }
    
    // MARK: - Text Inputs
    
    private var textInputsSection: some View {
        VStack(spacing: 12) {
            TextField("Top text", text: $topText)
                .textFieldStyle(MemeTextFieldStyle())
            
            TextField("Bottom text", text: $bottomText)
                .textFieldStyle(MemeTextFieldStyle())
        }
    }
    
    // MARK: - Customization
    
    private var customizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Customize")
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.primary)
            
            // Font size slider
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Size: \(Int(fontSize))")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.secondary)
                
                Slider(value: $fontSize, in: 20...60, step: 5)
                    .tint(.blue)
            }
            
            // Color pickers
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Text Color")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    ColorPicker("", selection: $textColor)
                        .labelsHidden()
                }
                
                VStack(alignment: .leading) {
                    Text("Outline")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                        .foregroundStyle(.secondary)
                    
                    ColorPicker("", selection: $textOutlineColor)
                        .labelsHidden()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
        )
    }
    
    // MARK: - Template Selector
    
    private var templateSelectorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Popular Templates")
                    .font(.custom("OpenSans-Bold", size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Upload", systemImage: "photo")
                        .font(.custom("OpenSans-SemiBold", size: 14))
                }
                .onChange(of: selectedItem) { _, newValue in
                    loadImage(from: newValue)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(MemeTemplate.faithMemes) { template in
                        TemplateCard(template: template, isSelected: selectedTemplate?.id == template.id) {
                            selectTemplate(template)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                generateMeme()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate Meme")
                }
                .font(.custom("OpenSans-Bold", size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(topText.isEmpty && bottomText.isEmpty)
            
            if generatedMeme != nil {
                HStack(spacing: 12) {
                    Button {
                        if let meme = generatedMeme {
                            onSend(meme)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "paperplane.fill")
                            Text("Send")
                        }
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    
                    Button {
                        showShareSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share")
                        }
                        .font(.custom("OpenSans-Bold", size: 16))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func selectTemplate(_ template: MemeTemplate) {
        selectedTemplate = template
        topText = template.topTextDefault
        bottomText = template.bottomTextDefault
        customImage = nil
    }
    
    private func loadImage(from item: PhotosPickerItem?) {
        Task {
            guard let item = item else { return }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    customImage = image
                    selectedTemplate = nil
                }
            }
        }
    }
    
    private func generateMeme() {
        let baseImage: UIImage?
        
        if let custom = customImage {
            baseImage = custom
        } else if let template = selectedTemplate {
            // In a real app, load the actual template image
            baseImage = createPlaceholderImage(for: template)
        } else {
            return
        }
        
        guard let base = baseImage else { return }
        
        // Generate meme with text overlay
        generatedMeme = overlayText(on: base)
        
        // Haptic feedback
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    private func createPlaceholderImage(for template: MemeTemplate) -> UIImage {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            UIColor.systemGray5.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            let text = template.name as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.label
            ]
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
    
    private func overlayText(on image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        
        return renderer.image { context in
            // Draw base image
            image.draw(at: .zero)
            
            // Prepare text attributes
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor(textColor),
                .strokeColor: UIColor(textOutlineColor),
                .strokeWidth: -3,
                .paragraphStyle: paragraphStyle
            ]
            
            // Draw top text
            if !topText.isEmpty {
                let topString = topText.uppercased() as NSString
                let topRect = CGRect(
                    x: 20,
                    y: 40,
                    width: image.size.width - 40,
                    height: fontSize + 20
                )
                topString.draw(in: topRect, withAttributes: attributes)
            }
            
            // Draw bottom text
            if !bottomText.isEmpty {
                let bottomString = bottomText.uppercased() as NSString
                let bottomRect = CGRect(
                    x: 20,
                    y: image.size.height - fontSize - 60,
                    width: image.size.width - 40,
                    height: fontSize + 20
                )
                bottomString.draw(in: bottomRect, withAttributes: attributes)
            }
        }
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    let template: MemeTemplate
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Template preview
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .cornerRadius(8)
                    .overlay(
                        Text("📸")
                            .font(.system(size: 40))
                    )
                
                Text(template.name)
                    .font(.custom("OpenSans-SemiBold", size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 120)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
    }
}

// MARK: - Custom Text Field Style

struct MemeTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.custom("OpenSans-SemiBold", size: 16))
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
            )
    }
}


