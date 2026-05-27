import SwiftUI

struct TypewriterText: View {
    let text: String
    var characterDelay: Duration = .milliseconds(24)
    var lineDelay: Duration = .milliseconds(180)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = ""
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Text(displayed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: displayed)
            .task(id: text) {
                revealTask?.cancel()

                guard !reduceMotion else {
                    displayed = text
                    return
                }

                displayed = ""
                revealTask = Task {
                    for character in text {
                        guard !Task.isCancelled else { return }
                        displayed.append(character)

                        if character == "\n" {
                            try? await Task.sleep(for: lineDelay)
                        } else {
                            try? await Task.sleep(for: characterDelay)
                        }
                    }
                }
            }
            .onDisappear {
                revealTask?.cancel()
            }
    }
}
