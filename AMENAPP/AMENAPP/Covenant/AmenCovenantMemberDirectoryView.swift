import SwiftUI
import FirebaseFirestore

// MARK: - Member Directory View
// Respects creator-configured visibility settings.
// Never exposes email addresses. Shows only display name, avatar, role, join date, badges.

struct AmenCovenantMemberDirectoryView: View {
    let covenantId: String
    let directoryVisibility: DirectoryVisibility

    enum DirectoryVisibility {
        case hidden
        case membersVisible
        case adminOnly
    }

    @State private var members: [CovenantMembership] = []
    @State private var loading = false
    @State private var searchText = ""
    @State private var selectedRole: CovenantMembership.MemberRole? = nil

    private var filtered: [CovenantMembership] {
        members.filter { m in
            let matchesSearch = searchText.isEmpty
            let matchesRole = selectedRole == nil || m.role == selectedRole
            return matchesSearch && matchesRole
        }
    }

    var body: some View {
        Group {
            switch directoryVisibility {
            case .hidden:
                hiddenState
            case .membersVisible, .adminOnly:
                directoryContent
            }
        }
        .task { await loadMembers() }
    }

    // MARK: - Hidden State

    private var hiddenState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Member Directory Hidden")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("The creator has set this community's member list to private.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Directory Content

    private var directoryContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search members…", text: $searchText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Role filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        roleFilterPill(nil, label: "All")
                        ForEach([CovenantMembership.MemberRole.creator, .admin, .moderator, .member], id: \.self) { role in
                            roleFilterPill(role, label: role.rawValue.capitalized)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)

                if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    List(filtered) { member in
                        MemberRow(membership: member)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Members (\(members.count))")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func roleFilterPill(_ role: CovenantMembership.MemberRole?, label: String) -> some View {
        let selected = selectedRole == role
        return Button { selectedRole = role } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Color.purple : Color(uiColor: .secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No members found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadMembers() async {
        loading = true
        members = (try? await CovenantService.shared.loadMembers(covenantId: covenantId)) ?? []
        loading = false
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let membership: CovenantMembership

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(membership.userId.prefix(2)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.purple)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Member")
                        .font(.subheadline.weight(.medium))
                    if membership.role != .member {
                        roleBadge(membership.role)
                    }
                }
                Text("Joined \(membership.joinedAt.dateValue(), style: .date)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusDot
        }
    }

    private func roleBadge(_ role: CovenantMembership.MemberRole) -> some View {
        let (label, color): (String, Color) = {
            switch role {
            case .creator:   return ("Creator", .purple)
            case .admin:     return ("Admin",   .orange)
            case .moderator: return ("Mod",     .teal)
            case .member:    return ("Member",  .secondary)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var statusDot: some View {
        Circle()
            .fill(membership.status.isActive ? Color.green : Color.secondary)
            .frame(width: 8, height: 8)
            .accessibilityLabel(membership.status.isActive ? "Active" : "Inactive")
    }
}
