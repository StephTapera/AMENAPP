//
//  AttachVerseSheet.swift
//  AMENAPP
//
//  Neumorphic Bible verse attachment for CreatePost
//

import SwiftUI
import Combine

// MARK: - Shared Neumorphic Theme
private let neuBG    = Color(red: 0.94, green: 0.94, blue: 0.96)
private let neuDark  = Color(red: 0.78, green: 0.78, blue: 0.82).opacity(0.8)
private let neuLight = Color.white.opacity(0.95)
private let accentR  = Color(red: 0.98, green: 0.42, blue: 0.32)
private let accentB  = Color(red: 0.35, green: 0.40, blue: 0.90)

// MARK: - Neumorphic Modifiers
private struct NeuRaised: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(neuBG)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: neuDark,  radius: 7, x: 4, y: 4)
            .shadow(color: neuLight, radius: 7, x: -4, y: -4)
    }
}

private struct NeuPressed: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(neuBG)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(neuDark, lineWidth: 1.5).blur(radius: 1).offset(x: 1.5, y: 1.5)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(neuLight, lineWidth: 1.5).blur(radius: 1).offset(x: -1.5, y: -1.5)
                    .mask(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
    }
}

extension View {
    fileprivate func neuRaised(_ r: CGFloat = 14) -> some View { modifier(NeuRaised(radius: r)) }
    fileprivate func neuPressed(_ r: CGFloat = 14) -> some View { modifier(NeuPressed(radius: r)) }
}

// MARK: - Models
struct BibleVerse: Identifiable, Equatable {
    let id = UUID()
    let reference: String
    let text: String
    let translation: String
}

enum BibleTranslation: String, CaseIterable {
    case NIV, ESV, KJV, NKJV, NLT, NASB
}

// MARK: - View Model
@MainActor
class AttachVerseViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedTranslation: BibleTranslation = .NIV
    @Published var results: [BibleVerse] = []
    @Published var selectedVerse: BibleVerse? = nil
    @Published var isLoading = false
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?

    let suggestions = ["strength", "peace", "Philippians 4:13", "John 3:16"]

    func search() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []; hasSearched = false; return
        }
        searchTask?.cancel()
        isLoading = true
        hasSearched = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.results = Self.mockSearch(self.searchText, translation: self.selectedTranslation)
                self.isLoading = false
            }
        }
    }

    func selectSuggestion(_ s: String) {
        searchText = s
        search()
    }

    private static func mockSearch(_ query: String, translation: BibleTranslation) -> [BibleVerse] {
        let bank: [BibleVerse] = [
            BibleVerse(reference: "Philippians 4:13", text: "I can do all things through Christ who strengthens me.", translation: translation.rawValue),
            BibleVerse(reference: "Isaiah 40:31", text: "But those who hope in the Lord will renew their strength. They will soar on wings like eagles.", translation: translation.rawValue),
            BibleVerse(reference: "Psalm 46:1", text: "God is our refuge and strength, an ever-present help in trouble.", translation: translation.rawValue),
            BibleVerse(reference: "John 3:16", text: "For God so loved the world that he gave his one and only Son, that whoever believes in him shall not perish but have eternal life.", translation: translation.rawValue),
            BibleVerse(reference: "Romans 8:28", text: "And we know that in all things God works for the good of those who love him.", translation: translation.rawValue),
            BibleVerse(reference: "Philippians 4:7", text: "And the peace of God, which transcends all understanding, will guard your hearts and your minds in Christ Jesus.", translation: translation.rawValue),
            BibleVerse(reference: "Isaiah 26:3", text: "You will keep in perfect peace those whose minds are steadfast, because they trust in you.", translation: translation.rawValue),
        ]
        let q = query.lowercased()
        return bank.filter {
            $0.reference.lowercased().contains(q) || $0.text.lowercased().contains(q)
        }
    }
}

// MARK: - Attach Verse Sheet
struct AttachVerseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AttachVerseViewModel()
    var onAttach: (BibleVerse) -> Void

    @State private var sheetOffset: CGFloat = 0
    @State private var cardScale: CGFloat = 0.92
    @State private var contentOpacity: Double = 0
    @State private var searchFocused = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            neuBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(neuDark)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                // Header
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Translation pills
                translationPicker
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                // Search
                searchField
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                // Body
                ZStack {
                    if vm.isLoading {
                        loadingView
                    } else if vm.hasSearched && vm.results.isEmpty {
                        emptyState
                    } else if !vm.results.isEmpty {
                        resultsList
                    } else {
                        emptyPrompt
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.results.count)
                .animation(.easeInOut(duration: 0.2), value: vm.isLoading)

                Spacer(minLength: 0)
            }
            .scaleEffect(cardScale)
            .opacity(contentOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                cardScale = 1.0
                contentOpacity = 1.0
            }
        }
    }

    // MARK: Header
    private var headerBar: some View {
        HStack {
            Button {
                animateDismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .neuRaised(12)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Attach Verse")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(white: 0.18))

            Spacer()

            Button {
                if let verse = vm.selectedVerse {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        onAttach(verse)
                        animateDismiss()
                    }
                }
            } label: {
                Text("Attach")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(vm.selectedVerse != nil ? accentB : Color(white: 0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        vm.selectedVerse != nil
                            ? accentB.opacity(0.12)
                            : neuBG
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: vm.selectedVerse != nil ? accentB.opacity(0.15) : .clear, radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(vm.selectedVerse == nil)
            .animation(.spring(response: 0.3), value: vm.selectedVerse != nil)
        }
    }

    // MARK: Translation Picker
    private var translationPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BibleTranslation.allCases, id: \.self) { t in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            vm.selectedTranslation = t
                        }
                        if vm.hasSearched { vm.search() }
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(vm.selectedTranslation == t ? .white : Color(white: 0.4))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(
                                vm.selectedTranslation == t
                                ? accentB
                                : neuBG
                            )
                            .clipShape(Capsule())
                            .shadow(
                                color: vm.selectedTranslation == t ? accentB.opacity(0.35) : neuDark,
                                radius: vm.selectedTranslation == t ? 8 : 5,
                                x: vm.selectedTranslation == t ? 0 : 3,
                                y: vm.selectedTranslation == t ? 4 : 3
                            )
                            .shadow(
                                color: vm.selectedTranslation == t ? .clear : neuLight,
                                radius: 5, x: -3, y: -3
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    // MARK: Search Field
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(inputFocused ? accentB : .secondary)
                .font(.system(size: 15, weight: inputFocused ? .semibold : .regular))
                .animation(.spring(response: 0.2), value: inputFocused)

            TextField("Search a verse or type reference (e.g. John 3:16)", text: $vm.searchText)
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.2))
                .focused($inputFocused)
                .submitLabel(.search)
                .onSubmit { vm.search() }
                .onChange(of: vm.searchText) { _ in
                    vm.search()
                }

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                    vm.results = []
                    vm.hasSearched = false
                    vm.selectedVerse = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(neuBG)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(inputFocused ? accentB.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: neuDark,  radius: 6, x: 3, y: 3)
        .shadow(color: neuLight, radius: 6, x: -3, y: -3)
        .animation(.spring(response: 0.25), value: inputFocused)
    }

    // MARK: Empty Prompt (no search yet)
    private var emptyPrompt: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated book icon
            ZStack {
                Circle()
                    .fill(accentB.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(accentB.opacity(0.6))
            }
            .padding(.top, 20)

            Text("Search by keyword or reference")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(white: 0.4))

            // Suggestion chips
            VStack(spacing: 10) {
                ForEach(vm.suggestions, id: \.self) { s in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            vm.selectSuggestion(s)
                        }
                    } label: {
                        Text("\"\(s)\"")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(accentB)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(accentB.opacity(0.08))
                            .clipShape(Capsule())
                            .shadow(color: accentB.opacity(0.1), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(accentB.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(loadingDotScale(i))
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: vm.isLoading
                        )
                }
            }
            Text("Searching scriptures...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .transition(.opacity)
    }

    @State private var dotPhase = false
    private func loadingDotScale(_ i: Int) -> CGFloat {
        vm.isLoading ? 1.4 : 1.0
    }

    // MARK: Empty State (searched, no results)
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundColor(Color(white: 0.6))
            Text("No verses found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color(white: 0.4))
            Text("Try a different keyword or reference")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Results List
    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, verse in
                    verseCard(verse, index: idx)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func verseCard(_ verse: BibleVerse, index: Int) -> some View {
        let isSelected = vm.selectedVerse?.id == verse.id

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                vm.selectedVerse = isSelected ? nil : verse
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(verse.reference)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isSelected ? accentB : Color(white: 0.2))

                        Text(verse.translation)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isSelected ? accentB : accentR)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((isSelected ? accentB : accentR).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Text(verse.text)
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: isSelected ? 0.2 : 0.4))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(isSelected ? accentB : neuBG)
                        .frame(width: 26, height: 26)
                        .shadow(color: isSelected ? accentB.opacity(0.3) : neuDark, radius: 4, x: 2, y: 2)
                        .shadow(color: isSelected ? .clear : neuLight, radius: 4, x: -2, y: -2)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.25), value: isSelected)
            }
            .padding(16)
            .background(
                isSelected
                    ? accentB.opacity(0.06)
                    : neuBG
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accentB.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: isSelected ? accentB.opacity(0.12) : neuDark, radius: isSelected ? 10 : 6, x: isSelected ? 0 : 3, y: isSelected ? 5 : 3)
            .shadow(color: isSelected ? .clear : neuLight, radius: 6, x: -3, y: -3)
            .scaleEffect(isSelected ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(
            .spring(response: 0.38, dampingFraction: 0.78)
            .delay(Double(index) * 0.04),
            value: vm.results.count
        )
    }

    // MARK: Dismiss
    private func animateDismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            cardScale = 0.92
            contentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

// MARK: - CreatePost Verse Attachment Badge
struct AttachedVerseBadge: View {
    let verse: BibleVerse
    var onRemove: () -> Void

    @State private var appear = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 13))
                .foregroundColor(accentB)

            VStack(alignment: .leading, spacing: 1) {
                Text(verse.reference)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentB)
                Text(verse.text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
                    .lineLimit(2)
            }

            Spacer()

            Button { onRemove() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(neuBG)
                    .clipShape(Circle())
                    .shadow(color: neuDark, radius: 3, x: 2, y: 2)
                    .shadow(color: neuLight, radius: 3, x: -2, y: -2)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(accentB.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentB.opacity(0.2), lineWidth: 1)
        )
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                appear = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    Color(red: 0.94, green: 0.94, blue: 0.96)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AttachVerseSheet { verse in
                print("Attached: \(verse.reference)")
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
}
