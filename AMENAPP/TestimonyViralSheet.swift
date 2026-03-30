// TestimonyViralSheet.swift
// AMEN App — Testimony Viral Generator
// Bottom sheet that transforms a testimony into platform-ready content

import SwiftUI
import Combine

// ─── MARK: Response Model ────────────────────────────────────────

struct ViralContent: Decodable {
    let title: String
    let captions: Captions
    let scripture: ViralScripture
    let hashtags: [String]
    let hook: String
    let contentIdeas: [String]

    struct Captions: Decodable {
        let short: String
        let medium: String
        let long: String
    }
    struct ViralScripture: Decodable {
        let reference: String
        let verse: String
        let why: String
    }
}

// ─── MARK: ViewModel ─────────────────────────────────────────────

@MainActor
final class ViralGeneratorViewModel: ObservableObject {
    @Published var result: ViralContent?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCaption: CaptionLength = .medium
    @Published var selectedPlatform: SocialPlatform = .instagram
    @Published var copiedField: String?

    enum CaptionLength: String, CaseIterable {
        case short = "Short", medium = "Medium", long = "Long"
    }
    enum SocialPlatform: String, CaseIterable {
        case instagram = "Instagram"
        case tiktok    = "TikTok"
        case twitter   = "Twitter/X"
        case facebook  = "Facebook"
    }

    func generate(testimony: String) {
        guard !testimony.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        result = nil

        Task {
            do {
                let prompt = BereanPrompts.viralGenerator(
                    testimony: testimony,
                    platform: selectedPlatform.rawValue
                )
                let content = try await ClaudeAPIService.shared.completeJSON(
                    system: prompt,
                    userMessage: "Generate viral content for this testimony.",
                    as: ViralContent.self,
                    maxTokens: 1200
                )
                result = content
            } catch {
                errorMessage = "Couldn't generate content. Try again."
            }
            isLoading = false
        }
    }

    var activeCaption: String {
        guard let r = result else { return "" }
        switch selectedCaption {
        case .short:  return r.captions.short
        case .medium: return r.captions.medium
        case .long:   return r.captions.long
        }
    }

    func copy(_ text: String, field: String) {
        UIPasteboard.general.string = text
        copiedField = field
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.copiedField = nil
        }
    }
}

// ─── MARK: Main Sheet ────────────────────────────────────────────

struct TestimonyViralSheet: View {
    let testimony: String
    @StateObject private var vm = ViralGeneratorViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showPlatformPicker = false

    var body: some View {
        ZStack {
            Color(hex: "0D0D1A").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 20)

                    headerSection

                    if vm.isLoading {
                        loadingSection
                    } else if let _ = vm.result {
                        resultSection
                    } else {
                        generateSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .onAppear { vm.generate(testimony: testimony) }
    }

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("VIRAL GENERATOR")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "C9A84C"))
                    .kerning(2)
                Text("Make It Shareable")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
            }
            Spacer()
            Button { showPlatformPicker = true } label: {
                HStack(spacing: 5) {
                    Text(vm.selectedPlatform.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(20)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            }
            .confirmationDialog("Platform", isPresented: $showPlatformPicker) {
                ForEach(ViralGeneratorViewModel.SocialPlatform.allCases, id: \.self) { p in
                    Button(p.rawValue) { vm.selectedPlatform = p; vm.generate(testimony: testimony) }
                }
            }
        }
        .padding(.bottom, 20)
    }

    private var loadingSection: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)
            ProgressView()
                .tint(Color(hex: "C9A84C"))
                .scaleEffect(1.5)
            Text("Berean AI is crafting your content...")
                .font(.system(size: 14))
                .foregroundColor(Color.white.opacity(0.5))
            Spacer(minLength: 60)
        }
    }

    private var generateSection: some View {
        VStack(spacing: 16) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "F09595"))
                    .multilineTextAlignment(.center)
            }
            Button("Generate Content") { vm.generate(testimony: testimony) }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(colors: [Color(hex: "C9A84C"), Color(hex: "F0D080")],
                                           startPoint: .leading, endPoint: .trailing))
                .cornerRadius(14)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let r = vm.result {
            VStack(spacing: 16) {
                // Title
                viralCard(label: "TITLE", content: r.title) { vm.copy(r.title, field: "title") }
                    .opacity(vm.copiedField == "title" ? 0.7 : 1)

                // Caption with length picker
                captionSection

                // Scripture
                VStack(alignment: .leading, spacing: 8) {
                    Text("SCRIPTURE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "C9A84C").opacity(0.7))
                        .kerning(1.5)
                    Text(r.scripture.reference)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "C9A84C"))
                    Text(r.scripture.verse)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                    Text(r.scripture.why)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.4))
                        .lineSpacing(3)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "C9A84C").opacity(0.07))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "C9A84C").opacity(0.2), lineWidth: 0.5))

                // Hashtags
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("HASHTAGS")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.4))
                            .kerning(1.5)
                        Spacer()
                        Button { vm.copy(r.hashtags.joined(separator: " "), field: "hashtags") } label: {
                            Text(vm.copiedField == "hashtags" ? "Copied!" : "Copy All")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(r.hashtags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "378ADD"))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color(hex: "378ADD").opacity(0.1))
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "378ADD").opacity(0.2), lineWidth: 0.5))
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 0.5))

                // Regenerate
                Button { vm.generate(testimony: testimony) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                        Text("Regenerate").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "C9A84C"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(hex: "C9A84C").opacity(0.1))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "C9A84C").opacity(0.25), lineWidth: 0.5))
                }
            }
        }
    }
    
    @ViewBuilder
    private var captionSection: some View {
        if let r = vm.result {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CAPTION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.4))
                        .kerning(1.5)
                    Spacer()
                    captionLengthPicker
                }
                Text(vm.activeCaption)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineSpacing(5)
                Button { vm.copy(vm.activeCaption, field: "caption") } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                        Text(vm.copiedField == "caption" ? "Copied!" : "Copy Caption")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color.white.opacity(0.5))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }
    
    private var captionLengthPicker: some View {
        HStack(spacing: 0) {
            ForEach(ViralGeneratorViewModel.CaptionLength.allCases, id: \.self) { len in
                captionLengthButton(len)
            }
        }
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
    
    private func captionLengthButton(_ len: ViralGeneratorViewModel.CaptionLength) -> some View {
        let isSelected = vm.selectedCaption == len
        return Button(len.rawValue) {
            vm.selectedCaption = len
        }
        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        .foregroundColor(isSelected ? .black : Color.white.opacity(0.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color(hex: "C9A84C") : Color.clear)
        .cornerRadius(12)
    }

    private func viralCard(label: String, content: String, onCopy: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.4))
                .kerning(1.5)
            Text(content)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                    Text("Copy").font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color.white.opacity(0.5))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}
