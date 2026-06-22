import SwiftUI
import FirebaseFunctions
import FirebaseAuth

// MARK: - AmenCovenantTierSetupSheet
//
// Allows the covenant creator to attach a Stripe Price ID to each tier.
// The Price ID must already exist in Stripe Dashboard — this sheet only
// stores the reference so createCovenantCheckoutSession can use it.

struct AmenCovenantTierSetupSheet: View {
    let covenantId: String

    @EnvironmentObject var vm: AmenCovenantViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var priceInputs: [String: String] = [:]
    @State private var savingTierId: String?
    @State private var savedTierIds: Set<String> = []
    @State private var errorMessage: String?

    private var tiers: [CovenantTier] {
        vm.currentCovenant?.tiers ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Enter the Stripe Price ID for each paid tier. Price IDs start with `price_` and are found in your Stripe Dashboard under Products.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init(top: 4, leading: 0, bottom: 8, trailing: 0))
                }

                if tiers.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Tiers Configured",
                            systemImage: "creditcard.trianglebadge.exclamationmark",
                            description: Text("Add paid tiers to your community before configuring Stripe prices.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(tiers) { tier in
                        tierRow(tier)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tier Pricing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                for tier in tiers {
                    priceInputs[tier.id] = tier.stripePriceId ?? ""  // stripePriceId set via Cloud Function
                }
            }
        }
    }

    // MARK: - Tier Row

    @ViewBuilder
    private func tierRow(_ tier: CovenantTier) -> some View {
        Section(header: tierHeader(tier)) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                TextField("price_xxxxxxxxxxxx", text: Binding(
                    get: { priceInputs[tier.id] ?? "" },
                    set: { priceInputs[tier.id] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.system(.body, design: .monospaced))

                saveButton(for: tier)
            }
        }
    }

    private func tierHeader(_ tier: CovenantTier) -> some View {
        HStack {
            Text(tier.name)
                .font(.footnote.bold())
            Text("·")
                .foregroundStyle(.secondary)
            Text(formattedPrice(tier))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if savedTierIds.contains(tier.id) {
                Spacer()
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func saveButton(for tier: CovenantTier) -> some View {
        let input = priceInputs[tier.id] ?? ""
        let isSaving = savingTierId == tier.id
        let isValid = input.hasPrefix("price_") && input.count > 7

        if isSaving {
            ProgressView()
                .scaleEffect(0.8)
        } else {
            Button {
                Task { await save(tier: tier, priceId: input) }
            } label: {
                Text("Save")
                    .font(.subheadline.bold())
                    .foregroundStyle(isValid ? Color.accentColor : Color.secondary)
            }
            .disabled(!isValid || isSaving)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Save Action

    private func save(tier: CovenantTier, priceId: String) async {
        errorMessage = nil
        savingTierId = tier.id
        defer { savingTierId = nil }

        let functions = Functions.functions(region: "us-central1")
        let callable = functions.httpsCallable("saveCovenantTierStripePriceId")

        do {
            _ = try await callable.call([
                "covenantId": covenantId,
                "tierId": tier.id,
                "stripePriceId": priceId.trimmingCharacters(in: .whitespaces),
            ])
            savedTierIds.insert(tier.id)
            // Refresh covenant so the updated stripePriceId is reflected in-memory.
            await vm.loadMembership(for: covenantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func formattedPrice(_ tier: CovenantTier) -> String {
        let symbol = tier.currency.uppercased() == "USD" ? "$" : tier.currency.uppercased() + " "
        let amount = String(format: "%.2f", tier.price)
        return "\(symbol)\(amount)\(tier.billingPeriod.displayLabel)"
    }
}
