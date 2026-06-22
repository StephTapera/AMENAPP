//
//  StickySectionLabel.swift
//  AMENAPP
//
//  Small glass section label for use inside `LazyVStack(pinnedViews: .sectionHeaders)`
//  (spec §6.6). Native sticky behaviour is provided by SwiftUI's pinned section headers;
//  this is only the chrome that pins. Built on `liquidGlassSurface` so it inherits the
//  native lens + fail-closed solid fallback.
//

import SwiftUI

struct StickySectionLabel: View {
    let title: String
    var systemImage: String?

    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AmenTheme.Colors.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .liquidGlassSurface(.light, emphasis: .none, in: Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
