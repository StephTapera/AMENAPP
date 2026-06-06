import SwiftUI

struct CatalogWorkTypeTabBar: View {

    let tabs: [CatalogTab]
    @Binding var selectedType: WorkType?
    var onSelect: (WorkType?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    if tab.count > 0 || tab.type == nil {
                        tabCapsule(tab: tab)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func tabCapsule(tab: CatalogTab) -> some View {
        let isSelected = selectedType == tab.type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                onSelect(tab.type)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(tab.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text("\(tab.count)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.primary)
                } else {
                    Capsule()
                        .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                }
            }
            .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : .primary)
        }
        .buttonStyle(.plain)
    }
}
