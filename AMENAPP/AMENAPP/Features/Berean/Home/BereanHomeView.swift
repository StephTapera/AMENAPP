// BereanHomeView.swift
// AMEN — Berean Reading Surface: Study Hub home screen (W2)
// Flag: bereanHomeV2 (default false)
// Screen struct: BereanStudyHubView
//
// States: empty / loading / error / offline — all wired.
// UGC: input text routes through BereanContextActionEngine (TODO comment).

import SwiftUI

struct BereanStudyHubView: View {

    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var isOffline = false
    @AppStorage("berean.lastStudy") private var lastStudyTitle: String = ""
    @AppStorage("berean.lastStudyDate") private var lastStudyTimestamp: Double = 0

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var hasLastStudy: Bool {
        !lastStudyTitle.isEmpty && Date().timeIntervalSince1970 - lastStudyTimestamp < 7 * 86400
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.bereanIvory.ignoresSafeArea()

            Group {
                if isLoading {
                    loadingView
                } else if let err = errorMessage {
                    errorView(err)
                } else {
                    contentView
                }
            }

            // Input bar pinned above keyboard
            VStack(spacing: 0) {
                Divider().opacity(0.2)
                BereanStudyInputBar(
                    text: $inputText,
                    placeholder: "Ask Berean…",
                    showMic: true,
                    onSend: submitInput,
                    onMic: { /* W3: open listening mode */ }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.bereanIvory.ignoresSafeArea(edges: .bottom))
            }
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 88) }
    }

    // MARK: - Subviews

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Greeting
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting)
                        .font(BereanReaderType.displayTitle)
                        .foregroundStyle(Color.bereanInk)
                    Text("What do you want to study today?")
                        .font(BereanType.body())
                        .foregroundStyle(Color.bereanInk.opacity(0.55))
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // Offline banner
                if isOffline {
                    offlineBanner
                }

                // Continue studying (if recent)
                if hasLastStudy {
                    BereanReaderCard(header: "Continue studying") {
                        Text(lastStudyTitle)
                            .font(BereanReaderType.body)
                            .foregroundStyle(Color.bereanInk)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 16)
                    .accessibilityHint("Tap to continue your last study session")
                }

                // Quick action chips
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(BereanHomeChip.allCases) { chip in
                        BereanActionPill(
                            label: chip.rawValue,
                            icon: chip.icon,
                            accessibilityHint: "Open \(chip.rawValue)",
                            onTap: { handleChip(chip) }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 120)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            WordGlowLoader()
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.bereanWine.opacity(0.7))
            Text(message)
                .font(BereanType.body())
                .foregroundStyle(Color.bereanInk.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                errorMessage = nil
            }
            .font(BereanType.subheadline())
            .foregroundStyle(Color.bereanInk)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.bereanTan)
            .clipShape(Capsule())
            .accessibilityLabel("Retry loading")
            Spacer()
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14))
            Text("Studying offline — some features unavailable")
                .font(BereanType.caption())
        }
        .foregroundStyle(Color.bereanInk.opacity(0.6))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bereanTan.opacity(0.4))
        .padding(.horizontal, 16)
        .accessibilityLabel("Offline mode — limited features available")
    }

    // MARK: - Actions

    private func handleChip(_ chip: BereanHomeChip) {
        // TODO: Route to appropriate Berean mode screen
        // .readScripture → BereanScriptureReaderView
        // .askBerean → BereanStudyInputBar focus
        // .sermonNotes → BereanNotesEditorView
        // .prayerJournal → BereanPrayerSurfaceView
        // .explainPassage, .dailyPlan → BereanContextActionEngine.perform(action: .ask)
    }

    private func submitInput() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        // TODO: Route through BereanContextActionEngine.perform(action: .askBerean, payload: [...])
        //       or BereanStudyService for study-specific callables
        //       All UGC (query) must pass through constitutional review gate before submission
        print("Berean query submitted: \(query)")
        lastStudyTitle = query
        lastStudyTimestamp = Date().timeIntervalSince1970
        inputText = ""
    }
}

#Preview {
    BereanStudyHubView()
}
