import SwiftUI

// MARK: - Selah Contextual Reader
// The self-contained "Read" action for any scripture-bearing suggestion. It fetches the
// passage text on demand through YouVersionBibleService (public-domain KJV by default,
// the same path the rest of the app uses) and renders it in a calm sheet. No dependency
// on external navigation seams — tapping "Read" always does something real.

/// Identifiable payload that drives the reader `.sheet(item:)`.
struct SelahContextualReaderRequest: Identifiable, Equatable {
    let id = UUID()
    let references: [String]
    let sourceFeature: SelahContextualFeature
}

/// Notifications the contextual surface emits for actions it can't fulfil itself.
extension Notification.Name {
    /// Posted when a bulletin/slide-capture suggestion is accepted; ContentView opens
    /// the camera (Camera OS) in response.
    static let selahOpenBulletinCapture = Notification.Name("selahOpenBulletinCapture")
}

private enum SelahReaderLoadState: Equatable {
    case loading
    case loaded([SelahLoadedPassage])
    case failed(String)
}

struct SelahLoadedPassage: Identifiable, Equatable {
    let id = UUID()
    let reference: String
    let text: String
}

struct SelahContextualReaderSheet: View {
    let request: SelahContextualReaderRequest
    @Environment(\.dismiss) private var dismiss
    @State private var state: SelahReaderLoadState = .loading

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("Opening passage…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    ContentUnavailableView(
                        "Couldn't open this passage",
                        systemImage: "book.closed",
                        description: Text(message)
                    )
                case .loaded(let passages):
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(passages) { passage in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(passage.reference)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                    Text(passage.text)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Selah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        var loaded: [SelahLoadedPassage] = []
        var firstError: String?
        for ref in request.references.prefix(5) {
            do {
                let passage = try await YouVersionBibleService.shared.fetchVerse(reference: ref)
                loaded.append(SelahLoadedPassage(reference: passage.reference, text: passage.text))
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }
        if loaded.isEmpty {
            state = .failed(firstError ?? "This passage isn't available right now.")
        } else {
            state = .loaded(loaded)
        }
    }
}
