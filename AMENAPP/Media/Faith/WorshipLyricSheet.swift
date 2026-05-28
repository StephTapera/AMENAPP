import SwiftUI

struct WorshipLyricSheet: View {
    @Binding var isPresented: Bool
    var trackTitle: String
    var artistName: String
    var lyrics: [LyricLine]

    @State private var currentTime: TimeInterval = 0
    @State private var lyricTimer: Timer?

    struct LyricLine: Identifiable {
        let id = UUID()
        var timestamp: TimeInterval
        var text: String
    }

    private var currentLineId: UUID? {
        let active = lyrics.filter { $0.timestamp <= currentTime }
        return active.last?.id
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if lyrics.isEmpty {
                            Text("Lyrics not available")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            ForEach(Array(lyrics.enumerated()), id: \.element.id) { idx, line in
                                let isCurrent = line.id == currentLineId
                                let isPast = line.timestamp < currentTime && !isCurrent

                                let fgStyle: AnyShapeStyle = isCurrent
                                    ? AnyShapeStyle(Color.amenGold)
                                    : isPast
                                        ? AnyShapeStyle(Color.primary.opacity(0.45))
                                        : AnyShapeStyle(Color.primary.opacity(0.72))
                                Text(line.text)
                                    .font(isCurrent ? .title3.bold() : .body)
                                    .foregroundStyle(fgStyle)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(line.id)
                                    .animation(.easeInOut(duration: 0.3), value: isCurrent)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .onChange(of: currentLineId) { _, newId in
                    if let id = newId {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .navigationTitle(trackTitle.isEmpty ? "Lyrics" : trackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
                if !artistName.isEmpty {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(trackTitle).font(.headline)
                            Text(artistName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .presentationBackground(.regularMaterial)
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentTime += 0.5
        }
    }

    private func stopTimer() {
        lyricTimer?.invalidate()
        lyricTimer = nil
    }
}
