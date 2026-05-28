import SwiftUI

struct SmartCommunityCrisisState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text("You're not alone")
                .font(.title2.weight(.bold))

            Text("If you're going through a difficult time, please reach out to someone who can help.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                crisisLink(
                    title: "988 Suicide & Crisis Lifeline",
                    subtitle: "Call or text 988",
                    url: "tel:988",
                    icon: "phone.fill",
                    color: .red
                )

                crisisLink(
                    title: "Crisis Text Line",
                    subtitle: "Text HOME to 741741",
                    url: "sms:741741",
                    icon: "message.fill",
                    color: .blue
                )
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func crisisLink(title: String, subtitle: String, url: String, icon: String, color: Color) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                .padding(14)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("\(title), \(subtitle)")
        }
    }
}
