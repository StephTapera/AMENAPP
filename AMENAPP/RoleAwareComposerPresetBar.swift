import SwiftUI

struct RoleAwareComposerPresetBar: View {
    let presets: [ComposerPresetKind]
    let onSelect: (ComposerPresetKind) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    Button { onSelect(preset) } label: {
                        Text(title(for: preset))
                            .font(.systemScaled(13, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func title(for preset: ComposerPresetKind) -> String {
        switch preset {
        case .reflection:         return "Reflection"
        case .prayerRequest:      return "Prayer Request"
        case .testimony:          return "Testimony"
        case .gratitude:          return "Gratitude"
        case .scriptureSharee:    return "Scripture Share"
        case .announcement:       return "Announcement"
        case .sermonRecap:        return "Sermon Recap"
        case .eventInvite:        return "Event Invite"
        case .ministryUpdate:     return "Ministry Update"
        case .congregationPrayer: return "Congregation Prayer"
        case .resourceShare:      return "Resource Share"
        case .opportunity:        return "Opportunity"
        case .missionUpdate:      return "Mission Update"
        case .featuredCampaign:   return "Featured Campaign"
        case .partnershipUpdate:  return "Partnership Update"
        case .featuredOffering:   return "Featured Offering"
        }
    }
}

struct RoleAwareComposerPresetBar_Previews: PreviewProvider {
    static var previews: some View {
        RoleAwareComposerPresetBar(
            presets: [.reflection, .prayerRequest, .testimony, .gratitude],
            onSelect: { _ in }
        )
        .padding(.vertical)
        .previewLayout(.sizeThatFits)
    }
}
