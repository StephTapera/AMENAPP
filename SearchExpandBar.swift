//
//  SearchExpandBar.swift
//  AMENAPP
//
//  Tap-to-expand search bar with live results dropdown.
//  Collapsed: small black pill with magnifying glass.
//  Expanded: full-width Liquid Glass search field with chevron close.
//  Consistent with AMEN's design language: OpenSans, spring animations, Liquid Glass.
//

import SwiftUI
import Combine

// MARK: - State Machine

private enum SearchBarState: Equatable {
    case collapsed
    case expanding
    case expandedIdle
    case typing
    case showingResults
    case collapsing
}

// MARK: - SearchExpandBar (Reusable Component)

struct SearchExpandBar: View {
    @Binding var query: String
    var results: [DiscoverySearchResult]
    var onQueryChanged: (String) -> Void
    var onSelectResult: (DiscoverySearchResult) -> Void
    var onClose: () -> Void

    // Layout
    @State private var barState: SearchBarState = .collapsed
    @State private var expandProgress: CGFloat = 0   // 0 = collapsed, 1 = expanded
    @FocusState private var fieldFocused: Bool
    @Namespace private var morphNS

    // Debounce
    @State private var debounceTask: Task<Void, Never>?

    // Derived helpers
    private var isExpanded: Bool { barState != .collapsed && barState != .collapsing }
    private var showDropdown: Bool { barState == .showingResults }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                // ── Collapsed button (fades out as bar expands) ──────────────
                collapsedButton
                    .opacity(expandProgress == 0 ? 1 : 0)
                    // Keep pointer-events off while expanded so it doesn't intercept taps
                    .allowsHitTesting(barState == .collapsed)

                // ── Expanded search bar ──────────────────────────────────────
                expandedBar
                    .opacity(expandProgress)
                    .allowsHitTesting(isExpanded)
            }
            .frame(height: 44)

            // ── Results dropdown ─────────────────────────────────────────────
            if showDropdown && !results.isEmpty {
                resultsDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: showDropdown)
        .onChange(of: query) { _, newVal in
            scheduleSearch(newVal)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                barState = newVal.isEmpty ? .expandedIdle : .typing
            }
        }
        .onChange(of: results) { _, newResults in
            if !newResults.isEmpty && !query.isEmpty {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    barState = .showingResults
                }
            }
        }
    }

    // MARK: - Collapsed Button

    private var collapsedButton: some View {
        Button {
            open()
        } label: {
            ZStack {
                // Black pill
                Capsule()
                    .fill(Color.primary)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Search")
    }

    // MARK: - Expanded Bar

    private var expandedBar: some View {
        HStack(spacing: 0) {
            // Left: magnifying glass icon
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 44)
                .padding(.leading, 4)

            // Text field
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search people, posts, churches...")
                        .font(.custom("OpenSans-Regular", size: 15))
                        .foregroundStyle(.tertiary)
                        .opacity(expandProgress)
                        .allowsHitTesting(false)
                }

                TextField("", text: $query)
                    .font(.custom("OpenSans-Regular", size: 15))
                    .foregroundStyle(.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        if !query.isEmpty {
                            onQueryChanged(query)
                        }
                    }
                    .accessibilityLabel("Search field")
            }
            .frame(maxWidth: .infinity)

            // Right: xmark close — chevron.right was confusing (looks like "go forward")
            Button {
                close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(width: 36, height: 44)
                    .padding(.trailing, 4)
            }
            .accessibilityLabel("Clear and close search")
        }
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
    }

    // MARK: - Results Dropdown

    private var resultsDropdown: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(results.prefix(8)) { result in
                    Button {
                        select(result)
                    } label: {
                        HStack(spacing: 12) {
                            // Icon circle
                            ZStack {
                                Circle()
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                    .frame(width: 36, height: 36)
                                Image(systemName: result.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name)
                                    .font(.custom("OpenSans-SemiBold", size: 15))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                if let subtitle = result.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.custom("OpenSans-Regular", size: 13))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(DiscoveryPressStyle())

                    if result.id != results.prefix(8).last?.id {
                        Divider()
                            .padding(.leading, 62)
                    }
                }
            }
        }
        .frame(maxHeight: CGFloat(min(results.prefix(8).count, 6)) * 58)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 6)
    }

    // MARK: - Actions

    private func open() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            barState = .expanding
            expandProgress = 1
        }
        // Focus after spring settles (~350ms)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            barState = .expandedIdle
            fieldFocused = true
        }
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        fieldFocused = false
        debounceTask?.cancel()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
            barState = .collapsing
            expandProgress = 0
        }
        // Clear after bar has retracted
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            query = ""
            barState = .collapsed
        }
        onClose()
    }

    private func select(_ result: DiscoverySearchResult) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        query = result.name
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            barState = .typing
        }
        onSelectResult(result)
    }

    private func scheduleSearch(_ newQuery: String) {
        debounceTask?.cancel()
        guard !newQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            onQueryChanged("")
            return
        }
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000) // 220ms debounce
            guard !Task.isCancelled else { return }
            onQueryChanged(newQuery)
        }
    }
}

// MARK: - DiscoverySearchResult Model

struct DiscoverySearchResult: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String?
    let icon: String          // SF Symbol name
    let resultType: ResultType

    enum ResultType: Equatable {
        case person(userId: String)
        case post(postId: String)
        case church(churchId: String)
        case topic(query: String)
    }
}

// MARK: - DiscoveryViewModel extension — build SearchExpandBar results

extension DiscoveryViewModel {
    /// Maps live search results into DiscoverySearchResult for the dropdown.
    var discoveryDropdownResults: [DiscoverySearchResult] {
        var out: [DiscoverySearchResult] = []

        for user in userResults.prefix(4) {
            let uid = user.id ?? UUID().uuidString
            out.append(DiscoverySearchResult(
                id: "u_\(uid)",
                name: user.displayName,
                subtitle: "@\(user.username)",
                icon: "person.circle",
                resultType: .person(userId: uid)
            ))
        }

        for post in postResults.prefix(3) {
            out.append(DiscoverySearchResult(
                id: "p_\(post.objectID)",
                name: post.authorName,
                subtitle: String(post.content.prefix(60)),
                icon: "doc.text",
                resultType: .post(postId: post.objectID)
            ))
        }

        // Fix #3: include church results in dropdown
        for church in churchResults.prefix(2) {
            out.append(DiscoverySearchResult(
                id: "c_\(church.id)",
                name: church.name,
                subtitle: church.denomination ?? (church.address.isEmpty ? nil : church.address),
                icon: "building.columns",
                resultType: .church(churchId: church.id)
            ))
        }

        return out
    }
}
