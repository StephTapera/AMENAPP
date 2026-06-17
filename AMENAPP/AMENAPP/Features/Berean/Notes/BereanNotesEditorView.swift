// BereanNotesEditorView.swift
// AMEN — Berean Reading Surface: Sermon & Study Notes Editor (W4)
// Flag: bereanNotesEditor (default false)
//
// Local-first: saves on every edit change via AppStorage.
// Offline: shows "Will sync when online" banner — never silent loss.
// All AI actions route through BereanContextActionEngine (TODO comment).

import SwiftUI

struct BereanNotesEditorView: View {

    @AppStorage("berean.notes.currentTitle") private var titleText: String = ""
    @AppStorage("berean.notes.currentBody") private var bodyText: String = ""

    @State private var isSyncing = false
    @State private var isOffline = false
    @State private var showOfflineBanner = false
    @State private var errorMessage: String? = nil
    @State private var lastAIAction: BereanAIAction? = nil
    @State private var showAIResultSheet = false
    @State private var aiResultText = ""

    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

    private var isEditing: Bool { titleFocused || bodyFocused }

    var body: some View {
        ZStack(alignment: .top) {
            Color.bereanWhite.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Offline / error banners
                if showOfflineBanner {
                    offlineBanner
                }
                if let err = errorMessage {
                    errorBanner(err)
                }

                // Title field
                TextField("Title", text: $titleText, axis: .vertical)
                    .font(BereanType.sectionTitle())
                    .foregroundStyle(Color.bereanInk)
                    .focused($titleFocused)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Note title")
                    .submitLabel(.next)
                    .onSubmit { bodyFocused = true }

                Divider()
                    .background(Color.bereanTan.opacity(0.6))
                    .padding(.horizontal, 20)

                // Body editor
                TextEditor(text: $bodyText)
                    .font(BereanReaderType.body)
                    .foregroundStyle(Color.bereanInk)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($bodyFocused)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .accessibilityLabel("Note body")

                // Sync indicator
                if isSyncing {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Syncing…")
                            .font(BereanType.caption())
                            .foregroundStyle(Color.bereanInk.opacity(0.45))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                AIKeyboardToolbar { action in handleAIAction(action) }
            }
        }
        .onChange(of: bodyText) { _, _ in autoSave() }
        .onChange(of: titleText) { _, _ in autoSave() }
        .sheet(isPresented: $showAIResultSheet) {
            aiResultSheet
        }
    }

    // MARK: - Banners

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash").font(.system(size: 13))
            Text("Will sync when online — your notes are saved locally")
                .font(BereanType.caption())
            Spacer()
            Button { showOfflineBanner = false } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
            .accessibilityLabel("Dismiss offline banner")
        }
        .foregroundStyle(Color.bereanInk.opacity(0.65))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bereanTan.opacity(0.4))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 13))
            Text(msg).font(BereanType.caption())
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark").font(.system(size: 11))
            }
        }
        .foregroundStyle(Color.bereanWine.opacity(0.8))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.bereanWine.opacity(0.08))
    }

    // MARK: - AI Result Sheet

    private var aiResultSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(lastAIAction?.displayName ?? "Berean Result")
                    .font(BereanType.sectionTitle())
                    .foregroundStyle(Color.bereanInk)
                Spacer()
                Button("Insert") {
                    bodyText += "\n\n\(aiResultText)"
                    showAIResultSheet = false
                }
                .font(BereanType.subheadline())
                .foregroundStyle(Color.bereanInk)
                Button("Done") { showAIResultSheet = false }
                    .font(BereanType.subheadline())
                    .foregroundStyle(Color.bereanInk.opacity(0.5))
            }
            .padding()

            ScrollView {
                Text(aiResultText)
                    .font(BereanReaderType.body)
                    .foregroundStyle(Color.bereanInk)
                    .padding()
            }
        }
        .background(Color.bereanIvory.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    // MARK: - Actions

    private func autoSave() {
        // AppStorage persists automatically — this is the local-first save.
        // TODO: Queue sync to Firestore via existing notes sync path when online.
        //       If offline: set showOfflineBanner = true, queue for later sync.
    }

    private func handleAIAction(_ action: BereanAIAction) {
        lastAIAction = action
        let notesContent = "\(titleText)\n\(bodyText)"
        // TODO: Route through BereanContextActionEngine.perform(action: action, payload: ["notes": notesContent])
        //       or BereanStudyService for study-specific callables.
        //       action.routesTo → .ask/.discern/.build — determines callable.
        //       UGC (notes body) must pass through constitutional review before submission.
        print("Notes AI action: \(action.displayName) → \(action.routesTo.rawValue)")
        // Stub result for preview
        aiResultText = "[\(action.displayName) result will appear here — routed to \(action.routesTo.rawValue) mode]"
        showAIResultSheet = true
    }
}

#Preview {
    BereanNotesEditorView()
}
