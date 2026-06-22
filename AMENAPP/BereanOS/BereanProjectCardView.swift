// BereanProjectCardView.swift
// AMENAPP — Berean OS

import SwiftUI

struct BereanProjectCardView: View {
    let project: BereanProject

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.title)
                .font(.headline)
                .lineLimit(1)
            Text(project.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Label(project.status.rawValue.capitalized, systemImage: statusIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(project.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusIcon: String {
        switch project.status {
        case .active:    return "circle.fill"
        case .paused:    return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .archived:  return "archivebox.fill"
        }
    }
}
