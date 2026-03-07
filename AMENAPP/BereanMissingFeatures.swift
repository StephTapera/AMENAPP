//
//  BereanMissingFeatures.swift
//  AMENAPP
//
//  Missing features implementation for Berean AI
//

import SwiftUI
import PhotosUI
import Speech
import AVFoundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - Image Picker

struct BereanImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: BereanImagePicker
        
        init(_ parent: BereanImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Plus Button Menu

struct BereanPlusMenu: View {
    @Binding var isShowing: Bool
    let onImageUpload: () -> Void
    let onBibleSearch: () -> Void
    let onSmartFeatures: () -> Void
    let onSavedPrompts: () -> Void
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isShowing = false
                    }
                }
            
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Quick Actions")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(white: 0.2))
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isShowing = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color(white: 0.4))
                        }
                    }
                    .padding()
                    .background(Color.white)
                    
                    Divider()
                    
                    // Action buttons
                    ScrollView {
                        VStack(spacing: 0) {
                            PlusMenuButton(
                                icon: "photo.on.rectangle",
                                title: "Upload Image",
                                subtitle: "Analyze scripture screenshots",
                                color: .blue
                            ) {
                                isShowing = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onImageUpload()
                                }
                            }
                            
                            Divider()
                                .padding(.leading, 60)
                            
                            PlusMenuButton(
                                icon: "magnifyingglass",
                                title: "Search Bible Passage",
                                subtitle: "Find and discuss specific verses",
                                color: .purple
                            ) {
                                isShowing = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onBibleSearch()
                                }
                            }
                            
                            Divider()
                                .padding(.leading, 60)
                            
                            PlusMenuButton(
                                icon: "star.circle",
                                title: "Smart Features",
                                subtitle: "Cross-references, Greek/Hebrew, more",
                                color: .orange
                            ) {
                                isShowing = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onSmartFeatures()
                                }
                            }
                            
                            Divider()
                                .padding(.leading, 60)
                            
                            PlusMenuButton(
                                icon: "bookmark.fill",
                                title: "Saved Prompts",
                                subtitle: "Quick access to common questions",
                                color: .green
                            ) {
                                isShowing = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onSavedPrompts()
                                }
                            }
                        }
                        .background(Color.white)
                    }
                    .frame(maxHeight: 400)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
                .padding(.horizontal, 20)
                .padding(.bottom, 0)
            }
        }
    }
}

struct PlusMenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(color.opacity(0.1))
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(white: 0.2))
                    
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.5))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Speech Recognition Service

@MainActor
class SpeechRecognitionService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var error: String?
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    func startRecording() throws {
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Stop the engine and remove any existing tap before re-configuring.
        // installTap(onBus:) throws an NSException (not a Swift error) if a tap
        // is already installed — this was the P0 crash on rapid double-taps or
        // background/foreground transitions that called startRecording() twice.
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognition", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false
        
        // Get audio input
        let inputNode = audioEngine.inputNode
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                Task { @MainActor in
                    self.transcribedText = result.bestTranscription.formattedString
                    isFinal = result.isFinal
                }
            }
            
            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                Task { @MainActor in
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isRecording = false
                    
                    if let error = error {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        
        // Configure audio tap
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        transcribedText = ""
        error = nil
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

// MARK: - Voice Input View

struct VoiceInputView: View {
    @ObservedObject var speechRecognizer: SpeechRecognitionService
    @Binding var isPresented: Bool
    let onComplete: (String) -> Void
    
    @State private var waveAmplitude: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    stopRecording()
                }
            
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 20) {
                    // Waveform visualization
                    HStack(spacing: 4) {
                        ForEach(0..<5) { index in
                            WaveformBar(
                                isAnimating: speechRecognizer.isRecording,
                                delay: Double(index) * 0.1
                            )
                        }
                    }
                    .frame(height: 60)
                    
                    // Status text
                    Text(speechRecognizer.isRecording ? "Listening..." : "Tap to start")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                    
                    // Transcribed text
                    if !speechRecognizer.transcribedText.isEmpty {
                        ScrollView {
                            Text(speechRecognizer.transcribedText)
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.1))
                        )
                    }
                    
                    // Error message
                    if let error = speechRecognizer.error {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }
                    
                    // Action buttons
                    HStack(spacing: 20) {
                        Button {
                            stopRecording()
                        } label: {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Cancel")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                            )
                        }
                        
                        if !speechRecognizer.transcribedText.isEmpty {
                            Button {
                                completeRecording()
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Use Text")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 14)
                                .background(
                                    Capsule()
                                        .fill(.white)
                                )
                            }
                        }
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(white: 0.15))
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
                )
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
    }
    
    private func stopRecording() {
        speechRecognizer.stopRecording()
        isPresented = false
    }
    
    private func completeRecording() {
        let text = speechRecognizer.transcribedText
        speechRecognizer.stopRecording()
        isPresented = false
        onComplete(text)
    }
}

struct WaveformBar: View {
    let isAnimating: Bool
    let delay: Double
    
    @State private var height: CGFloat = 10
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.white)
            .frame(width: 8, height: height)
            .animation(
                isAnimating ?
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay) :
                    .default,
                value: height
            )
            .onAppear {
                if isAnimating {
                    height = CGFloat.random(in: 20...60)
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                height = newValue ? CGFloat.random(in: 20...60) : 10
            }
    }
}

// MARK: - Verse Detail View

struct VerseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let verseReference: String
    
    @State private var verseText: String = ""
    @State private var isLoading = true
    @State private var translations: [String: String] = [:]
    @State private var selectedTranslation = "NIV"
    
    let availableTranslations = ["NIV", "ESV", "KJV", "NLT", "NASB"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.96, green: 0.96, blue: 0.96)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Reference
                        Text(verseReference)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(white: 0.2))
                        
                        // Translation picker
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableTranslations, id: \.self) { translation in
                                    Button {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedTranslation = translation
                                        }
                                    } label: {
                                        Text(translation)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(selectedTranslation == translation ? .white : Color(white: 0.4))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(
                                                Capsule()
                                                    .fill(selectedTranslation == translation ? Color.black : Color.white)
                                            )
                                    }
                                }
                            }
                        }
                        
                        // Verse text
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 40)
                        } else {
                            Text(verseText)
                                .font(.custom("Georgia", size: 18))
                                .foregroundStyle(Color(white: 0.2))
                                .lineSpacing(8)
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
                                )
                        }
                        
                        // Actions
                        VStack(spacing: 12) {
                            BereanActionButton(
                                icon: "square.and.arrow.up",
                                title: "Share Verse",
                                color: .blue
                            ) {
                                shareVerse()
                            }
                            
                            BereanActionButton(
                                icon: "bookmark",
                                title: "Save to Favorites",
                                color: .orange
                            ) {
                                saveVerse()
                            }
                            
                            BereanActionButton(
                                icon: "doc.text",
                                title: "Copy Text",
                                color: .green
                            ) {
                                copyVerse()
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Scripture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(white: 0.3))
                    }
                }
            }
        }
        .onAppear {
            loadVerseText()
        }
    }
    
    private func loadVerseText() {
        Task {
            do {
                let passage = try await YouVersionBibleService.shared.fetchVerse(
                    reference: verseReference,
                    version: .esv
                )
                await MainActor.run {
                    verseText = passage.text
                    translations["ESV"] = passage.text
                    isLoading = false
                }
            } catch {
                // Fallback: show a polite "unavailable" message rather than crashing
                await MainActor.run {
                    verseText = "Verse text unavailable. Please check your connection and try again."
                    isLoading = false
                }
            }
        }
    }
    
    private func shareVerse() {
        let text = "\"\(verseText)\"\n\n— \(verseReference) (\(selectedTranslation))"
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func saveVerse() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        Task {
            _ = try? await Firestore.firestore()
                .collection("users").document(userId)
                .collection("savedVerses")
                .addDocument(data: [
                    "reference": verseReference,
                    "text": verseText,
                    "translation": selectedTranslation,
                    "savedAt": FieldValue.serverTimestamp()
                ])
        }
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
    
    private func copyVerse() {
        UIPasteboard.general.string = "\"\(verseText)\"\n\n— \(verseReference) (\(selectedTranslation))"
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)
    }
}

struct BereanActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(color)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
            )
        }
    }
}

// MARK: - Report Issue View

struct BereanReportIssueView: View {
    @Environment(\.dismiss) private var dismiss
    let message: BereanMessage
    @Binding var isPresented: Bool
    
    @State private var issueType: IssueType = .incorrect
    @State private var description = ""
    @State private var isSubmitting = false
    
    enum IssueType: String, CaseIterable {
        case incorrect = "Incorrect Information"
        case inappropriate = "Inappropriate Content"
        case technical = "Technical Issue"
        case other = "Other"
        
        var icon: String {
            switch self {
            case .incorrect: return "exclamationmark.triangle"
            case .inappropriate: return "hand.raised"
            case .technical: return "wrench.and.screwdriver"
            case .other: return "ellipsis.circle"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Issue Type") {
                    Picker("Type", selection: $issueType) {
                        ForEach(IssueType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.rawValue)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section("Message Content") {
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.4))
                        .padding(.vertical, 8)
                }
                
                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                        .font(.system(size: 15))
                }
                
                Section {
                    Button {
                        submitReport()
                    } label: {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Submit Report")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(description.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        Task {
            let db = Firestore.firestore()
            _ = try? await db.collection("bereanFeedback").addDocument(data: [
                "userId": Auth.auth().currentUser?.uid ?? "anonymous",
                "messageContent": message.content,
                "issueType": issueType.rawValue,
                "description": description,
                "submittedAt": FieldValue.serverTimestamp()
            ])
            await MainActor.run {
                isSubmitting = false
                isPresented = false
                let haptic = UINotificationFeedbackGenerator()
                haptic.notificationOccurred(.success)
            }
        }
    }
}
