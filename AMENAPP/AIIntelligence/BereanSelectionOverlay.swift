import SwiftUI

struct BereanSelectionOverlay<Content: View>: View {
    let payload: BereanContextPayload
    let content: Content

    @ObservedObject private var engine = BereanContextActionEngine.shared // PERF: singleton → @ObservedObject
    @ObservedObject private var manager = BereanContextMenuManager.shared

    init(payload: BereanContextPayload, @ViewBuilder content: () -> Content) {
        self.payload = payload
        self.content = content()
    }

    var body: some View {
        content
            .contextMenu {
                ForEach(manager.actions(for: payload).prefix(12)) { action in
                    Button {
                        manager.activate(payload: payload, action: action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            }
            .accessibilityHint("Long press for Berean actions")
            .sheet(isPresented: $manager.showingResult) {
                BereanContextResultSheet(engine: engine, manager: manager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}

struct BereanContextResultSheet: View {
    @ObservedObject var engine: BereanContextActionEngine
    @ObservedObject var manager: BereanContextMenuManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                if engine.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .accessibilityLabel("Loading Berean response")
                        Text("Berean is reading the context")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else if let result = engine.lastResult {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            AmenAIUsageLabel(text: "AI-assisted Berean response")
                            Text(result.answer)
                                .font(.body)
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .accessibilityLabel("Berean response")

                            if !result.scriptureReferences.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Scripture")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(result.scriptureReferences, id: \.self) { reference in
                                        Label(reference, systemImage: "book.closed")
                                            .font(.subheadline)
                                    }
                                }
                                .accessibilityElement(children: .contain)
                            }

                            if let notice = result.safetyNotice, !notice.isEmpty {
                                Text(notice)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel("AI safety notice: \(notice)")
                            }

                            if !result.suggestedActions.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Next")
                                        .font(.subheadline.weight(.semibold))
                                    ForEach(result.suggestedActions, id: \.self) { action in
                                        Label(action, systemImage: "arrow.right.circle")
                                            .font(.subheadline)
                                    }
                                }
                                .accessibilityElement(children: .contain)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 14) {
                        ContentUnavailableView(
                            "Berean could not answer",
                            systemImage: "exclamationmark.triangle",
                            description: Text(engine.lastErrorMessage ?? "Please try again.")
                        )
                        Button {
                            manager.retryActiveAction()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Retry Berean action")
                    }
                    .padding()
                }
            }
            .navigationTitle(engine.lastResult?.title ?? manager.selectedAction?.title ?? "Ask Berean")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if engine.isLoading {
                        Button("Cancel") {
                            manager.cancelActiveAction()
                            dismiss()
                        }
                        .accessibilityLabel("Cancel Berean action")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        engine.clearResult()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BereanContextActionModifier: ViewModifier {
    let payload: BereanContextPayload

    func body(content: Content) -> some View {
        BereanSelectionOverlay(payload: payload) {
            content
        }
    }
}

extension View {
    func bereanContextActions(payload: BereanContextPayload) -> some View {
        modifier(BereanContextActionModifier(payload: payload))
    }
}
