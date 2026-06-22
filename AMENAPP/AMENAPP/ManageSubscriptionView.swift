import SwiftUI
import StoreKit
import UIKit

struct ManageSubscriptionView: View {
    @StateObject private var premium = PremiumManager.shared
    @StateObject private var studio = StudioSubscriptionService.shared

    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var showRestoreAlert = false

    var body: some View {
        List {
            // ── AMEN Pro (StoreKit 2) ──────────────────────────────────────
            Section {
                LabeledContent("AMEN Pro") {
                    Text(premium.hasProAccess ? "Active" : "Free")
                        .foregroundStyle(premium.hasProAccess ? .green : .secondary)
                        .fontWeight(.medium)
                }

                if !premium.hasProAccess {
                    LabeledContent("Messages remaining today") {
                        Text("\(premium.freeMessagesRemaining) / \(premium.FREE_MESSAGES_PER_DAY)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("AMEN Pro")
            }

            // ── Studio Subscription (RevenueCat) ──────────────────────────
            Section {
                LabeledContent("Studio Tier") {
                    Text(studio.entitlement.displayName)
                        .foregroundStyle(studio.entitlement != .free ? .green : .secondary)
                        .fontWeight(.medium)
                }
            } header: {
                Text("AMEN Studio")
            }

            // ── Actions ───────────────────────────────────────────────────
            Section {
                Button {
                    openAppStoreSubscriptions()
                } label: {
                    Label("Manage in App Store", systemImage: "arrow.up.right.square")
                }

                Button {
                    Task { await restorePurchases() }
                } label: {
                    if isRestoring {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Restoring…")
                        }
                    } else {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRestoring)
            } header: {
                Text("Actions")
            } footer: {
                Text("Tap \"Manage in App Store\" to cancel or change your subscription. Restoring purchases re-links any active subscription to this account.")
                    .font(.caption)
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Restore Purchases", isPresented: $showRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .task { await premium.loadProducts() }
    }

    private func openAppStoreSubscriptions() {
        AMENAnalyticsService.shared.track(.manageSubscriptionOpened(surface: "settings_subscription"))
        guard let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    private func restorePurchases() async {
        isRestoring = true
        let restored = await premium.restorePurchases()
        #if canImport(RevenueCat)
        await studio.restore()
        #endif
        isRestoring = false
        if restored || studio.entitlement != .free {
            restoreMessage = "Your subscription has been restored."
        } else {
            restoreMessage = premium.purchaseError ?? "No active subscription found on this Apple ID."
        }
        showRestoreAlert = true
    }
}
