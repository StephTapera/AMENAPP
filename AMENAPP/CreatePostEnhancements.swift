//
//  CreatePostEnhancements.swift
//  AMENAPP
//
//  Industry-standard post creation enhancements
//  Phase 1: Alt text, Hide engagement, Content warning
//  Phase 2: Voice-to-text, AI verse suggestions, Preview
//  Phase 3: Image crop, Templates, Threads
//

import SwiftUI
import Speech
import PhotosUI

// MARK: - Phase 1: Alt Text Editor Sheet

struct AltTextEditorSheet: View {
    @Binding var altText: String
    @Environment(\.dismiss) var dismiss
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a description for screen readers and users who can't see the image.")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                TextEditor(text: $altText)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .frame(height: 150)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .focused($isFocused)
                    .padding(.horizontal)
                
                HStack {
                    Text("\(altText.count)/1000")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(altText.count > 1000 ? .red : .secondary)
                    
                    Spacer()
                    
                    if !altText.isEmpty {
                        Button("Clear") {
                            altText = ""
                        }
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Image Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 16))
                        .disabled(altText.count > 1000)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Phase 1: Image Preview with Alt Text Button

struct ImagePreviewWithAltText: View {
    let imageData: Data
    let altText: String
    let index: Int
    let onRemove: () -> Void
    let onEditAltText: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .background(
                        Circle()
                            .fill(.black.opacity(0.6))
                            .frame(width: 22, height: 22)
                    )
            }
            .offset(x: 8, y: -8)
            
            // Alt text indicator
            VStack {
                Spacer()
                
                Button {
                    onEditAltText()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: altText.isEmpty ? "text.bubble" : "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(altText.isEmpty ? "ALT" : "ALT ✓")
                            .font(.custom("OpenSans-Bold", size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(altText.isEmpty ? Color.black.opacity(0.7) : Color.green.opacity(0.8))
                    )
                    .foregroundStyle(.white)
                }
                .padding(8)
            }
        }
        .frame(width: 160, height: 160)
    }
}

// MARK: - Phase 1: Engagement Privacy Settings

struct EngagementPrivacyRow: View {
    @Binding var hideEngagementCounts: Bool
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                hideEngagementCounts.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: hideEngagementCounts ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.purple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide Engagement Counts")
                        .font(.custom("OpenSans-SemiBold", size: 15))
                        .foregroundStyle(.primary)
                    Text("Others won't see likes and interactions")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $hideEngagementCounts)
                    .labelsHidden()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phase 1: Content Warning Settings

struct ContentWarningRow: View {
    @Binding var hasSensitiveContent: Bool
    @Binding var sensitiveContentReason: String
    @State private var showReasonSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                if hasSensitiveContent {
                    showReasonSheet = true
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        hasSensitiveContent = true
                        showReasonSheet = true
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sensitive Content Warning")
                            .font(.custom("OpenSans-SemiBold", size: 15))
                            .foregroundStyle(.primary)
                        Text("Mark for grief, trauma, or difficult topics")
                            .font(.custom("OpenSans-Regular", size: 12))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $hasSensitiveContent)
                        .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            
            if hasSensitiveContent && !sensitiveContentReason.isEmpty {
                HStack {
                    Text("Reason: \(sensitiveContentReason)")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") {
                        showReasonSheet = true
                    }
                    .font(.custom("OpenSans-Regular", size: 13))
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 74)
                .padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $showReasonSheet) {
            SensitiveContentReasonSheet(
                reason: $sensitiveContentReason,
                isMarked: $hasSensitiveContent
            )
        }
    }
}

struct SensitiveContentReasonSheet: View {
    @Binding var reason: String
    @Binding var isMarked: Bool
    @Environment(\.dismiss) var dismiss
    
    let suggestedReasons = [
        "Grief or Loss",
        "Mental Health",
        "Trauma or Abuse",
        "Medical Discussion",
        "Other"
    ]
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This helps prepare readers for sensitive content")
                    .font(.custom("OpenSans-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                ForEach(suggestedReasons, id: \.self) { suggestion in
                    Button {
                        reason = suggestion
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.custom("OpenSans-Regular", size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if reason == suggestion {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(reason == suggestion ? Color.orange.opacity(0.1) : Color.clear)
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Content Warning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isMarked = false
                        reason = ""
                        dismiss()
                    }
                    .font(.custom("OpenSans-Regular", size: 16))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.custom("OpenSans-SemiBold", size: 16))
                    .disabled(reason.isEmpty)
                }
            }
        }
    }
}

// MARK: - Phase 2: Voice-to-Text Button

struct VoiceToTextButton: View {
    @Binding var isRecording: Bool
    @Binding var postText: String
    let onRequestPermission: () -> Void
    let onToggleRecording: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button {
            onToggleRecording()
        } label: {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(.red.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .scaleEffect(pulseScale)
                }
                
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isRecording ? .red : .secondary)
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Phase 2: AI Verse Suggestions Banner

struct AIVerseSuggestionsBanner: View {
    let suggestedVerses: [ScripturePassage]
    let isLoading: Bool
    let onSelectVerse: (ScripturePassage) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("Berean suggests these verses")
                    .font(.custom("OpenSans-SemiBold", size: 14))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing your post...")
                        .font(.custom("OpenSans-Regular", size: 13))
                        .foregroundStyle(.secondary)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestedVerses.prefix(3), id: \.reference) { verse in
                            Button {
                                onSelectVerse(verse)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verse.reference)
                                        .font(.custom("OpenSans-SemiBold", size: 12))
                                        .foregroundStyle(.purple)
                                    Text(String(verse.text.prefix(60)) + "...")
                                        .font(.custom("OpenSans-Regular", size: 11))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(10)
                                .frame(width: 160)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(.ultraThinMaterial)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.purple.opacity(0.05))
        )
        .padding(.horizontal)
    }
}

// MARK: - Phase 2: Post Preview Mode

struct PostPreviewSheet: View {
    let postText: String
    let category: Post.PostCategory
    let images: [Data]
    let verseReference: String
    let verseText: String
    let hasSensitiveContent: Bool
    let sensitiveContentReason: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Preview")
                        .font(.custom("OpenSans-Bold", size: 24))
                        .padding(.horizontal)
                    
                    // Post card preview (simplified)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(.gray.opacity(0.3))
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Name")
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                Text("Just now")
                                    .font(.custom("OpenSans-Regular", size: 13))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if hasSensitiveContent {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sensitive Content")
                                        .font(.custom("OpenSans-SemiBold", size: 13))
                                    Text(sensitiveContentReason)
                                        .font(.custom("OpenSans-Regular", size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        Text(postText)
                            .font(.custom("OpenSans-Regular", size: 15))
                        
                        if !images.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(images.indices, id: \.self) { index in
                                    if let uiImage = UIImage(data: images[index]) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                        }
                        
                        if !verseReference.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verseReference)
                                    .font(.custom("OpenSans-SemiBold", size: 13))
                                    .foregroundStyle(.indigo)
                                Text(verseText)
                                    .font(.custom("OpenSans-Regular", size: 14))
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.indigo.opacity(0.05))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 8)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Post Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.custom("OpenSans-SemiBold", size: 16))
                }
            }
        }
    }
}

// MARK: - Speech Recognition Service

@MainActor
class SpeechRecognitionService: ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var isRecording = false
    @Published var transcribedText = ""
    
    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    func startRecording() throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognizer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognizer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.transcribedText = result.bestTranscription.formattedString
            }
            
            if error != nil || result?.isFinal == true {
                self.stopRecording()
            }
        }
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}
