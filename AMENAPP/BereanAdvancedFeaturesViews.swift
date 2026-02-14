//
//  BereanAdvancedFeaturesViews.swift
//  AMENAPP
//
//  Advanced AI features UI for Berean Pro
//

import SwiftUI

// MARK: - Devotional Generator View

struct DevotionalGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var genkitService = BereanGenkitService.shared
    
    @State private var topic = ""
    @State private var devotional: Devotional?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Berean background
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        Color(red: 0.96, green: 0.95, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "book.pages.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.purple, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Daily Devotional")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Color(white: 0.2))
                            
                            Text("Generate personalized daily devotionals powered by AI")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(white: 0.4))
                                .lineSpacing(4)
                        }
                        .padding(.top, 20)
                        
                        if devotional == nil {
                            // Input form
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Topic (Optional)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.4))
                                    .textCase(.uppercase)
                                    .tracking(1)
                                
                                TextField("e.g., Faith, Hope, Love", text: $topic)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color(white: 0.3))
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.5))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color(white: 0.85), lineWidth: 1)
                                            )
                                    )
                                    .disabled(isGenerating)
                                
                                Text("Leave blank for a random devotional")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(white: 0.5))
                            }
                            
                            Button {
                                generateDevotional()
                            } label: {
                                HStack {
                                    if isGenerating {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Generate Devotional")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.purple, Color.blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: Color.purple.opacity(0.3), radius: 10, y: 4)
                                )
                            }
                            .disabled(isGenerating)
                            .opacity(isGenerating ? 0.6 : 1.0)
                            
                            if let error = errorMessage {
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.red.opacity(0.1))
                                    )
                            }
                        } else {
                            // Display devotional
                            DevotionalDisplay(devotional: devotional!) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    devotional = nil
                                    topic = ""
                                    errorMessage = nil
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Devotional")
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
    }
    
    private func generateDevotional() {
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await genkitService.generateDevotional(
                    topic: topic.isEmpty ? nil : topic
                )
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        devotional = result
                        isGenerating = false
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate devotional. Please try again."
                    isGenerating = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

struct DevotionalDisplay: View {
    let devotional: Devotional
    let onReset: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(devotional.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(white: 0.2))
            
            // Scripture
            VStack(alignment: .leading, spacing: 8) {
                Text("Scripture")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                    .textCase(.uppercase)
                    .tracking(1.5)
                
                Text(devotional.scripture)
                    .font(.custom("Georgia", size: 16))
                    .italic()
                    .foregroundStyle(Color(white: 0.3))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.6))
                    )
            }
            
            // Content
            Text(devotional.content)
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.3))
                .lineSpacing(6)
            
            // Prayer
            VStack(alignment: .leading, spacing: 8) {
                Text("Prayer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                    .textCase(.uppercase)
                    .tracking(1.5)
                
                Text(devotional.prayer)
                    .font(.custom("Georgia", size: 15))
                    .italic()
                    .foregroundStyle(Color(white: 0.3))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.05))
                    )
            }
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    shareDevotional()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.4))
                    )
                }
                
                Button {
                    onReset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("New Devotional")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
            }
        }
    }
    
    private func shareDevotional() {
        let text = """
        \(devotional.title)
        
        \(devotional.scripture)
        
        \(devotional.content)
        
        Prayer:
        \(devotional.prayer)
        
        — Generated by Berean AI
        """
        
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
}

// MARK: - Study Plan Generator View

struct StudyPlanGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var genkitService = BereanGenkitService.shared
    
    @State private var topic = ""
    @State private var duration = 7
    @State private var studyPlan: StudyPlan?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    
    let durationOptions = [7, 14, 21, 30]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        Color(red: 0.96, green: 0.95, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.green, Color.blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Study Plan Generator")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Color(white: 0.2))
                            
                            Text("Create personalized Bible study plans")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(white: 0.4))
                        }
                        .padding(.top, 20)
                        
                        if studyPlan == nil {
                            // Input form
                            VStack(alignment: .leading, spacing: 20) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Study Topic")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.4))
                                        .textCase(.uppercase)
                                        .tracking(1)
                                    
                                    TextField("e.g., The Gospel of John", text: $topic)
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color(white: 0.3))
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.5))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color(white: 0.85), lineWidth: 1)
                                                )
                                        )
                                        .disabled(isGenerating)
                                }
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Duration")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.4))
                                        .textCase(.uppercase)
                                        .tracking(1)
                                    
                                    HStack(spacing: 12) {
                                        ForEach(durationOptions, id: \.self) { days in
                                            DurationButton(
                                                days: days,
                                                isSelected: duration == days
                                            ) {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    duration = days
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Button {
                                generateStudyPlan()
                            } label: {
                                HStack {
                                    if isGenerating {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Generate Plan")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.green, Color.blue],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: Color.green.opacity(0.3), radius: 10, y: 4)
                                )
                            }
                            .disabled(topic.isEmpty || isGenerating)
                            .opacity((topic.isEmpty || isGenerating) ? 0.5 : 1.0)
                            
                            if let error = errorMessage {
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.red.opacity(0.1))
                                    )
                            }
                        } else {
                            // Display study plan
                            StudyPlanDisplay(plan: studyPlan!) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    studyPlan = nil
                                    topic = ""
                                    errorMessage = nil
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Study Plan")
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
    }
    
    private func generateStudyPlan() {
        isGenerating = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await genkitService.generateStudyPlan(
                    topic: topic,
                    duration: duration
                )
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        studyPlan = result
                        isGenerating = false
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to generate study plan. Please try again."
                    isGenerating = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

struct DurationButton: View {
    let days: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(days)")
                    .font(.system(size: 20, weight: .bold))
                Text("days")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : Color(white: 0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        isSelected ?
                            LinearGradient(
                                colors: [Color.green, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                colors: [Color.white.opacity(0.5), Color.white.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StudyPlanDisplay: View {
    let plan: StudyPlan
    let onReset: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(plan.title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(white: 0.2))
            
            Text(plan.description)
                .font(.system(size: 15))
                .foregroundStyle(Color(white: 0.3))
                .lineSpacing(6)
            
            Text("\(plan.duration) • \(Int(plan.progress * 100))% Complete")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.5))
            
            HStack(spacing: 12) {
                Button {
                    // Share logic
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.4))
                    )
                }
                
                Button {
                    onReset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("New Plan")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
            }
        }
    }
}

// MARK: - Scripture Analyzer View

struct ScriptureAnalyzerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var genkitService = BereanGenkitService.shared
    
    @State private var reference = ""
    @State private var analysisType: ScriptureAnalysisType = .context
    @State private var analysis: String?
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        Color(red: 0.96, green: 0.95, blue: 0.94)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "text.magnifyingglass")
                                .font(.system(size: 44))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Scripture Analyzer")
                                .font(.system(size: 32, weight: .light))
                                .foregroundStyle(Color(white: 0.2))
                            
                            Text("Deep dive into Scripture with AI analysis")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(white: 0.4))
                        }
                        .padding(.top, 20)
                        
                        if analysis == nil {
                            // Input form
                            VStack(alignment: .leading, spacing: 20) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Scripture Reference")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.4))
                                        .textCase(.uppercase)
                                        .tracking(1)
                                    
                                    TextField("e.g., John 3:16", text: $reference)
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color(white: 0.3))
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.5))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color(white: 0.85), lineWidth: 1)
                                                )
                                        )
                                        .disabled(isAnalyzing)
                                }
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Analysis Type")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color(white: 0.4))
                                        .textCase(.uppercase)
                                        .tracking(1)
                                    
                                    VStack(spacing: 8) {
                                        ForEach(ScriptureAnalysisType.allCases, id: \.self) { type in
                                            AnalysisTypeButton(
                                                type: type,
                                                isSelected: analysisType == type
                                            ) {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    analysisType = type
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            
                            Button {
                                analyzeScripture()
                            } label: {
                                HStack {
                                    if isAnalyzing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text("Analyze Scripture")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .shadow(color: Color.blue.opacity(0.3), radius: 10, y: 4)
                                )
                            }
                            .disabled(reference.isEmpty || isAnalyzing)
                            .opacity((reference.isEmpty || isAnalyzing) ? 0.5 : 1.0)
                            
                            if let error = errorMessage {
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.red.opacity(0.1))
                                    )
                            }
                        } else {
                            // Display analysis
                            VStack(alignment: .leading, spacing: 16) {
                                Text(reference)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color(white: 0.2))
                                
                                Text(analysisType.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.1))
                                    )
                                
                                Text(analysis!)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color(white: 0.3))
                                    .lineSpacing(6)
                                
                                Button {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        analysis = nil
                                        reference = ""
                                        errorMessage = nil
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("New Analysis")
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue, Color.purple],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Analyzer")
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
    }
    
    private func analyzeScripture() {
        isAnalyzing = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await genkitService.analyzeScripture(
                    reference: reference,
                    analysisType: analysisType
                )
                
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        analysis = result
                        isAnalyzing = false
                    }
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to analyze scripture. Please try again."
                    isAnalyzing = false
                    
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.error)
                }
            }
        }
    }
}

struct AnalysisTypeButton: View {
    let type: ScriptureAnalysisType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(type.rawValue)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(white: 0.2) : Color(white: 0.4))
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.blue)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Scripture Analysis Type Enum

enum ScriptureAnalysisType: String, CaseIterable {
    case context = "Historical Context"
    case theological = "Theological Themes"
    case practical = "Practical Application"
    case literary = "Literary Analysis"
}
