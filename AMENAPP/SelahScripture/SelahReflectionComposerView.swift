//
//  SelahReflectionComposerView.swift
//  AMENAPP
//
//  Phase 3b — Reflections & Privacy
//  Main reflection-writing interface, launched from the Lens bar "Reflect"
//  action. Reflections are private by default; sharing is an explicit,
//  post-save opt-in gated on a clean safety classification.
//

import SwiftUI

struct SelahReflectionComposerView: View {

    @ObservedObject var viewModel: SelahReflectionViewModel
    let verseReference: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: Local UI state
    @State private var showSavedToast: Bool = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Header
                    headerRow

                    // MARK: Text editor
                    textEditorSection

                    // MARK: Character counter
                    HStack {
                        Spacer()
                        Text("\(viewModel.reflectionText.count) / 8000")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: Share scope (only after successful save with clean safety)
                    if viewModel.savedSuccessfully,
                       let result = viewModel.safetyResult,
                       result.canShare {
                        shareScopeSection
                    }

                    // MARK: Error
                    if let error = viewModel.saveError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                    }

                    // MARK: Save button
                    saveButton
                }
                .padding()
            }

            // MARK: Toast
            if showSavedToast {
                VStack {
                    Spacer()
                    toastView
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(edges: .bottom)
                .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: showSavedToast)
            }
        }
        .background(.regularMaterial)
        // MARK: Safety banner sheet
        .sheet(isPresented: $viewModel.showSupportBanner) {
            if let payload = viewModel.safetyResult?.supportPayload {
                SelahSafetyBannerView(
                    payload: payload,
                    onDismiss: { viewModel.showSupportBanner = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        // MARK: Saved successfully → toast + auto-dismiss
        .onChange(of: viewModel.savedSuccessfully) { _, newValue in
            guard newValue else { return }
            dismissTask?.cancel()
            withAnimation(reduceMotion ? nil : .default) { showSavedToast = true }
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                dismiss()
            }
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("Reflect on \(verseReference)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("reflection.dismissButton")
        }
    }

    private var textEditorSection: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.reflectionText.isEmpty {
                Text("What is God saying to you through this verse?")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $viewModel.reflectionText)
                .font(.body)
                .frame(minHeight: 160)
                .scrollContentBackground(.hidden)
                .onChange(of: viewModel.reflectionText) { _, newValue in
                    if newValue.count > 8000 {
                        viewModel.reflectionText = String(newValue.prefix(8000))
                    }
                }
                .accessibilityIdentifier("reflection.textEditor")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        )
    }

    private var shareScopeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share with")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Picker("Share scope", selection: Binding(
                get: { viewModel.shareScope },
                set: { viewModel.updateShareScope($0) }
            )) {
                ForEach(SelahReflectionShareScope.allCases) { scope in
                    Text(scope.displayLabel)
                        .tag(scope)
                        .accessibilityIdentifier("reflection.shareScope.\(scope.rawValue)")
                }
            }
            .pickerStyle(.segmented)

            if viewModel.shareScope == .accountabilityPartner {
                TextField("Partner username or UID", text: Binding(
                    get: { viewModel.sharedWithUid ?? "" },
                    set: { viewModel.sharedWithUid = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                )
                .accessibilityIdentifier("reflection.partnerIdField")
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: viewModel.shareScope)
            }

            if viewModel.shareScope == .namedGroup {
                TextField("Group ID", text: Binding(
                    get: { viewModel.sharedWithGroupId ?? "" },
                    set: { viewModel.sharedWithGroupId = $0.isEmpty ? nil : $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                )
                .accessibilityIdentifier("reflection.groupIdField")
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.2), value: viewModel.shareScope)
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task { await viewModel.save() }
        } label: {
            ZStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Save Reflection")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(saveButtonEnabled ? Color.accentColor : Color.secondary.opacity(0.3))
            )
            .foregroundStyle(.white)
        }
        .disabled(!saveButtonEnabled)
        .accessibilityIdentifier("reflection.saveButton")
    }

    private var saveButtonEnabled: Bool {
        !viewModel.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSaving
    }

    private var toastView: some View {
        Text("Saved privately")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
            )
    }
}

// MARK: - Share scope display labels

private extension SelahReflectionShareScope {
    var displayLabel: String {
        switch self {
        case .justMe:                return "Just Me"
        case .accountabilityPartner: return "Accountability Partner"
        case .namedGroup:            return "Group"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SelahReflectionComposerView(
        viewModel: SelahReflectionViewModel(),
        verseReference: "Psalm 1:3"
    )
}
#endif
