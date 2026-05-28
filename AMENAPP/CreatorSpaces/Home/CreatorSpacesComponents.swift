import SwiftUI

struct CreatorSpaceHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AMENFont.bold(30))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(AMENFont.medium(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .amenGlassSurface(shape: .rounded(28), background: .balanced, placement: .inline)
    }
}

struct CreatorSpaceBanner: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
                .amenGlassSurface(shape: .rounded(16), background: .quiet, placement: .inline)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AMENFont.semiBold(18))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(16)
        .amenGlassSurface(shape: .rounded(24), background: .balanced, placement: .inline)
    }
}

struct CreatorStatusPanel: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
                .amenGlassSurface(shape: .rounded(13), background: .quiet, placement: .inline)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AMENFont.semiBold(15))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(AMENFont.medium(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
    }
}

struct SmartClipCard: View {
    let title: String
    let source: String

    var body: some View {
        CreatorSpaceBanner(title: title, subtitle: source, systemImage: "waveform.and.magnifyingglass")
    }
}

struct EventMemoryTimeline: View {
    let moments: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collective Memory")
                .font(AMENFont.semiBold(16))
                .foregroundStyle(.secondary)
            ForEach(moments, id: \.self) { moment in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 10, height: 10)
                    Text(moment)
                        .font(AMENFont.medium(13))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .amenGlassSurface(shape: .rounded(22), background: .balanced, placement: .inline)
    }
}

struct SpaceMediaRail: View {
    let titles: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(titles, id: \.self) { title in
                    Text(title)
                        .font(AMENFont.semiBold(13))
                        .foregroundStyle(.primary)
                        .frame(width: 136, height: 78)
                        .amenGlassSurface(shape: .rounded(18), background: .quiet, placement: .inline)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
