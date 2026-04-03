import SwiftUI

struct RoleAwareSetupChecklistView: View {
    let items: [SetupChecklistItemKind]
    @State private var completed: Set<SetupChecklistItemKind> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Get Started")
                .font(.systemScaled(17, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ForEach(items, id: \.self) { item in
                ChecklistRow(
                    item: item,
                    isCompleted: completed.contains(item),
                    onToggle: {
                        if completed.contains(item) {
                            completed.remove(item)
                        } else {
                            completed.insert(item)
                        }
                    }
                )

                if item != items.last {
                    Divider()
                        .padding(.leading, 52)
                }
            }

            // Progress footer
            let pct = items.isEmpty ? 0.0 : Double(completed.count) / Double(items.count)
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.black)
                            .frame(width: geo.size.width * pct, height: 4)
                            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: pct)
                    }
                }
                .frame(height: 4)

                Text("\(completed.count) of \(items.count) complete")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .liquidGlassCard()
        .padding(.horizontal, 16)
    }
}

private struct ChecklistRow: View {
    let item: SetupChecklistItemKind
    let isCompleted: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isCompleted ? Color.black : Color.black.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                    if isCompleted {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.systemScaled(11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isCompleted)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: item))
                        .font(.systemScaled(15, weight: .medium))
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .strikethrough(isCompleted, color: .secondary)

                    if let sub = subtitle(for: item) {
                        Text(sub)
                            .font(.systemScaled(12))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.systemScaled(12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func title(for item: SetupChecklistItemKind) -> String {
        switch item {
        case .addProfilePhoto:              return "Add a profile photo"
        case .writeIntro:                   return "Write your intro"
        case .chooseScriptureTopics:        return "Choose scripture topics"
        case .shareFirstReflection:         return "Share your first reflection"
        case .connectChurch:                return "Connect to a church"
        case .startFirstPrayer:             return "Start your first prayer"
        case .startVerification:            return "Start verification"
        case .addServiceTimes:              return "Add service times"
        case .addLocation:                  return "Add your location"
        case .createFirstAnnouncement:      return "Create your first announcement"
        case .uploadLogo:                   return "Upload your logo"
        case .assignStaffRoles:             return "Assign staff roles"
        case .addSermonSource:              return "Add sermon source"
        case .addCategory:                  return "Add a business category"
        case .addWebsite:                   return "Add your website"
        case .writeMissionStatement:        return "Write your mission statement"
        case .featureFirstResource:         return "Feature your first resource"
        case .configureAnalytics:           return "Configure analytics"
        case .createFirstProfessionalPost:  return "Create your first post"
        }
    }

    private func subtitle(for item: SetupChecklistItemKind) -> String? {
        switch item {
        case .addProfilePhoto:              return "Help people recognize you"
        case .writeIntro:                   return "Tell your story"
        case .chooseScriptureTopics:        return "Personalize your feed"
        case .shareFirstReflection:         return "Start the conversation"
        case .connectChurch:                return "Join your faith community"
        case .startFirstPrayer:             return "Begin your prayer journey"
        case .startVerification:            return "Build trust with your community"
        case .addServiceTimes:              return "Let visitors plan their visit"
        case .addLocation:                  return "Help people find you"
        case .createFirstAnnouncement:      return "Welcome your congregation"
        case .uploadLogo:                   return "Show your church identity"
        case .assignStaffRoles:             return "Organize your team"
        case .addSermonSource:              return "Share your teachings"
        case .addCategory:                  return "Help people discover you"
        case .addWebsite:                   return "Connect your online presence"
        case .writeMissionStatement:        return "Share your purpose"
        case .featureFirstResource:         return "Showcase what you offer"
        case .configureAnalytics:           return "Track your impact"
        case .createFirstProfessionalPost:  return "Start sharing your work"
        }
    }
}

struct RoleAwareSetupChecklistView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            RoleAwareSetupChecklistView(items: [
                .addProfilePhoto,
                .writeIntro,
                .chooseScriptureTopics,
                .shareFirstReflection
            ])
            .padding(.vertical)
        }
        .background(Color(white: 0.96))
    }
}
