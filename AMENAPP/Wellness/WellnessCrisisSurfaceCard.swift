import SwiftUI

// MARK: - Crisis Surface Card

struct WellnessCrisisSurfaceCard: View {
    @Binding var friendExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Red header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "exclamationmark")
                        .font(.systemScaled(13, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Need help now?")
                    .font(.custom("OpenSans-Bold", size: 15))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color(red: 0.72, green: 0.09, blue: 0.09))

            // Resource rows
            VStack(spacing: 0) {
                WellnessCrisisRow(
                    icon: "phone.fill",
                    iconColor: Color(red: 0.75, green: 0.10, blue: 0.10),
                    iconBg: Color(red: 0.98, green: 0.91, blue: 0.91),
                    title: "988 Suicide & Crisis Lifeline",
                    subtitle: "Call or Text 988"
                )
                Divider().padding(.leading, 74)

                WellnessCrisisRow(
                    icon: "message.fill",
                    iconColor: Color(red: 0.80, green: 0.44, blue: 0.06),
                    iconBg: Color(red: 0.99, green: 0.94, blue: 0.88),
                    title: "Crisis Text Line",
                    subtitle: "Text HOME to 741741"
                )
                Divider().padding(.leading, 74)

                WellnessCrisisRow(
                    icon: "cross.fill",
                    iconColor: Color(red: 0.10, green: 0.30, blue: 0.72),
                    iconBg: Color(red: 0.88, green: 0.92, blue: 0.99),
                    title: "Emergency Services",
                    subtitle: "Call 911"
                )
                Divider().padding(.leading, 74)

                // For a Friend — promoted
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                        friendExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.90, green: 0.88, blue: 0.99))
                                .frame(width: 44, height: 44)
                            Image(systemName: "heart.text.square.fill")
                                .font(.systemScaled(20))
                                .foregroundStyle(Color(red: 0.40, green: 0.20, blue: 0.72))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("For a Friend")
                                    .font(.custom("OpenSans-Bold", size: 16))
                                    .foregroundStyle(.primary)
                                Text("Promoted")
                                    .font(.custom("OpenSans-SemiBold", size: 10))
                                    .foregroundStyle(Color(red: 0.60, green: 0.08, blue: 0.38))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(red: 0.98, green: 0.90, blue: 0.95))
                                    .clipShape(Capsule())
                            }
                            Text("Supporting someone in crisis — what to say, what not to say")
                                .font(.custom("OpenSans-Regular", size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: friendExpanded ? "chevron.up" : "chevron.down")
                            .font(.systemScaled(13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("For a Friend — supporting someone in crisis")
                .accessibilityHint(friendExpanded ? "Collapse" : "Expand for guidance")

                if friendExpanded {
                    WellnessForAFriendExpanded()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.cornerRadiusLarge)
                .stroke(.white.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 14, y: 6)
    }
}

// MARK: - Crisis Row

private struct WellnessCrisisRow: View {
    let icon: String
    let iconColor: Color
    let iconBg: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconBg)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.systemScaled(19))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("OpenSans-Regular", size: 16))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.custom("OpenSans-SemiBold", size: 13))
                    .foregroundStyle(iconColor)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.systemScaled(15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(subtitle)")
    }
}

// MARK: - For a Friend Expanded

private struct WellnessForAFriendExpanded: View {
    private let guidance: [(icon: String, text: String)] = [
        ("checkmark.circle.fill", "Say: \"I'm here with you. Do you want me to stay while we call someone?\""),
        ("xmark.circle.fill", "Don't say: \"You just need more faith\" or \"snap out of it.\""),
        ("phone.fill", "If risk feels immediate, call 988 or emergency services yourself."),
        ("heart.fill", "Set limits compassionately. Supporting someone is not carrying everything alone."),
    ]
    private let colors: [Color] = [.green, .red, Color(red: 0.72, green: 0.10, blue: 0.10), Color(red: 0.52, green: 0.18, blue: 0.62)]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(guidance.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.systemScaled(14))
                        .foregroundStyle(colors[i])
                        .frame(width: 20)
                        .padding(.top, 2)
                    Text(item.text)
                        .font(.custom("OpenSans-Regular", size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 14)
        .padding(.top, 4)
    }
}
