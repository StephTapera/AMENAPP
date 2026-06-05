// AmenScholarshipAccessView.swift
// AMEN Spaces — Monetization: Scholarship / access-code redemption sheet.
//
// Glass rule: sheet chrome uses .ultraThinMaterial header strip;
//             code field and result card are matte.
// Presented as a .sheet — consumer wraps in sheet(isPresented:).
// Written: 2026-06-03

import SwiftUI
import FirebaseFunctions

// MARK: - View State

private enum ScholarshipViewState {
    case idle
    case loading
    case success(tierName: String, expiresAt: Date?, grantedBy: String)
    case error(String)
}

// MARK: - View

struct AmenScholarshipAccessView: View {
    let spaceId: String
    let spaceName: String
    let onAccessGranted: (AmenSpaceSubscriptionTier) -> Void
    let onDismiss: () -> Void

    @State private var code: String = ""
    @State private var viewState: ScholarshipViewState = .idle
    @State private var requestSubmitted: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var codeIsEmpty: Bool {
        code.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Color(hex: "070607").ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        subtitleBlock
                        codeEntryBlock
                        applyButton
                        stateDisplay
                        Spacer(minLength: 0)
                        scholarshipRequestLink
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header

    private var sheetHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Spacer().frame(height: 24)
                Text("Enter Access Code")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.25)
                    }
            )

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .padding(9)
                    .background(
                        Circle().fill(.ultraThinMaterial)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    )
            }
            .accessibilityLabel("Dismiss access code sheet")
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
    }

    // MARK: - Subtitle

    private var subtitleBlock: some View {
        Text("Churches, nonprofits, and ministry partners may provide free access codes to their community.")
            .font(.system(size: 14))
            .foregroundStyle(Color.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Churches, nonprofits, and ministry partners may provide free access codes to their community.")
    }

    // MARK: - Code Entry

    private var codeEntryBlock: some View {
        TextField("ACCESS CODE", text: $code)
            .font(.system(size: 24, weight: .bold))
            .tracking(4)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .onChange(of: code) { _, newValue in
                // Uppercase enforcement + max length
                let upper = newValue.uppercased()
                let trimmed = String(upper.prefix(20))
                if code != trimmed { code = trimmed }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                codeIsEmpty
                                    ? Color.white.opacity(0.15)
                                    : Color(hex: "D9A441"),
                                lineWidth: codeIsEmpty ? 1 : 2
                            )
                    )
            )
            .accessibilityLabel("Access code field, uppercase, maximum 20 characters")
    }

    // MARK: - Apply Button

    private var applyButton: some View {
        Button(action: redeemCode) {
            Group {
                if case .loading = viewState {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color(hex: "D9A441"))
                } else {
                    Text("Apply Code")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "070607"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    codeIsEmpty
                        ? Color(hex: "D9A441").opacity(0.30)
                        : Color(hex: "D9A441")
                )
        )
        .buttonStyle(.plain)
        .disabled(codeIsEmpty || { if case .loading = viewState { return true }; return false }())
        .accessibilityLabel(codeIsEmpty ? "Apply code — enter a code first" : "Apply access code")
    }

    // MARK: - State Display

    @ViewBuilder
    private var stateDisplay: some View {
        switch viewState {
        case .idle:
            EmptyView()

        case .loading:
            EmptyView()

        case .success(let tierName, let expiresAt, _):
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))
                    .accessibilityHidden(true)

                Text("Access Granted")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.white)

                Text(tierName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "D9A441"))

                if let expiresAt {
                    Text("Valid until \(expiresAt.formatted(.dateTime.month(.wide).day().year()))")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .accessibilityLabel("Valid until \(expiresAt.formatted(.dateTime.month(.wide).day().year()))")
                } else {
                    Text("No expiry date")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "D9A441").opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(hex: "D9A441").opacity(0.40), lineWidth: 1)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Access granted for \(tierName).")
            .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))

        case .error(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.red.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .accessibilityLabel("Error: \(message)")
        }
    }

    // MARK: - Scholarship Request Link

    private var scholarshipRequestLink: some View {
        VStack(spacing: 8) {
            Button(action: submitScholarshipRequest) {
                Text("Request a scholarship")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "D9A441").opacity(requestSubmitted ? 0.50 : 1.0))
                    .underline()
            }
            .buttonStyle(.plain)
            .disabled(requestSubmitted)
            .accessibilityLabel(requestSubmitted ? "Scholarship request submitted" : "Request a scholarship for this space")

            if requestSubmitted {
                Text("Request submitted")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel("Scholarship request submitted successfully")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: requestSubmitted)
    }

    // MARK: - Actions

    private func redeemCode() {
        let trimmedCode = code.trimmingCharacters(in: .whitespaces)
        guard !trimmedCode.isEmpty else { return }

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            viewState = .loading
        }

        Task {
            do {
                let callable = Functions.functions().httpsCallable("redeemScholarshipCode")
                let result = try await callable.call([
                    "spaceId": spaceId,
                    "code": trimmedCode,
                ])

                guard let data = result.data as? [String: Any] else {
                    await MainActor.run {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            viewState = .error("Unexpected response from server. Please try again.")
                        }
                    }
                    return
                }

                // Parse tier from response
                let tierData = data["tier"] as? [String: Any] ?? [:]
                let tier = parseTier(from: tierData)
                let expiresAtSeconds = data["expiresAt"] as? TimeInterval
                let expiresAt = expiresAtSeconds.map { Date(timeIntervalSince1970: $0) }
                let grantedBy = data["grantedBy"] as? String ?? ""

                await MainActor.run {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72)) {
                        viewState = .success(
                            tierName: tier?.name ?? "Access",
                            expiresAt: expiresAt,
                            grantedBy: grantedBy
                        )
                    }
                    if let tier {
                        onAccessGranted(tier)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        viewState = .error("That code wasn't found or has already been used.")
                    }
                }
            }
        }
    }

    private func submitScholarshipRequest() {
        Task {
            do {
                let callable = Functions.functions().httpsCallable("submitScholarshipRequest")
                _ = try await callable.call(["spaceId": spaceId])
                await MainActor.run {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                        requestSubmitted = true
                    }
                }
            } catch {
                // Fire-and-forget; no destructive consequence on failure
            }
        }
    }

    /// Attempts to construct an `AmenSpaceSubscriptionTier` from a raw
    /// dictionary returned by the `redeemScholarshipCode` CF.
    /// Returns nil if required fields are missing.
    private func parseTier(from dict: [String: Any]) -> AmenSpaceSubscriptionTier? {
        guard
            let id = dict["id"] as? String,
            let name = dict["name"] as? String
        else { return nil }

        return AmenSpaceSubscriptionTier(
            id: id,
            spaceId: spaceId,
            name: name,
            description: dict["description"] as? String ?? "",
            monthlyPriceCents: dict["monthlyPriceCents"] as? Int ?? 0,
            annualPriceCents: dict["annualPriceCents"] as? Int,
            features: dict["features"] as? [String] ?? [],
            order: dict["order"] as? Int ?? 0,
            isActive: dict["isActive"] as? Bool ?? true,
            isFreeTier: dict["isFreeTier"] as? Bool ?? false,
            storeKitProductId: dict["storeKitProductId"] as? String,
            introMonths: dict["introMonths"] as? Int,
            introPriceCents: dict["introPriceCents"] as? Int,
            createdAt: {
                if let ts = dict["createdAt"] as? TimeInterval {
                    return Date(timeIntervalSince1970: ts)
                }
                return Date()
            }()
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    AmenScholarshipAccessView(
        spaceId: "s1",
        spaceName: "Reformation Church",
        onAccessGranted: { _ in },
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
#endif
