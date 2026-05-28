import SwiftUI
import AVKit

struct GroupWatchSessionView: View {
    var sessionId: String
    var mediaURL: URL

    @StateObject private var coordinator = GroupWatchCoordinator()
    @State private var player: AVPlayer?
    @State private var showChat = true

    var body: some View {
        ZStack(alignment: .trailing) {
            // Video player
            Group {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Color.black
                }
            }
            .ignoresSafeArea()

            // Chat panel
            if showChat {
                GroupWatchChatPanel(
                    sessionId: sessionId,
                    participants: coordinator.participants
                )
                .frame(width: 280)
                .transition(.move(edge: .trailing))
            }

            // Chat toggle
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            showChat.toggle()
                        }
                    } label: {
                        Image(systemName: showChat ? "chevron.right" : "bubble.left.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .accessibilityLabel(showChat ? "Hide chat" : "Show chat")
                }
                Spacer()
            }
        }
        .onAppear {
            let p = AVPlayer(url: mediaURL)
            player = p
            coordinator.join(sessionId: sessionId, player: p)
            p.play()
        }
        .onDisappear {
            coordinator.leave()
            player?.pause()
        }
    }
}

struct GroupWatchChatPanel: View {
    var sessionId: String
    var participants: [String]

    @State private var messageText = ""
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            // Participants header
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                Text("\(participants.count) watching")
                    .font(.caption.bold())
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Color.white.opacity(0.2))

            // Messages list (placeholder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat messages appear here")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(12)
                }
            }

            Divider().background(Color.white.opacity(0.2))

            // Input
            HStack(spacing: 8) {
                TextField("Message...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.15)))

                Button {
                    messageText = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty)
                .accessibilityLabel("Send message")
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background {
            if reduceTransparency {
                Color.black.opacity(0.88)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }
}
