import SwiftUI

struct GivingFAQSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let faqs: [(String, String)] = [
        ("Is my donation secure?", "All transactions are processed through Stripe with bank-level encryption. AMEN never stores your payment credentials."),
        ("Can I set a recurring gift?", "Yes. When completing a donation you can choose Monthly or Annual cadence. You can cancel or modify at any time from your profile."),
        ("How do I get a tax receipt?", "A receipt is emailed immediately after each donation. You can also download a year-end summary from Tax Center in your profile."),
        ("Which organizations are verified?", "Every organization on AMEN has completed our nonprofit verification process, including 501(c)(3) confirmation and basic governance review."),
        ("Can I give anonymously?", "Yes. Toggle 'Give Anonymously' before confirming your donation. The organization receives the funds but not your name."),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(faqs, id: \.0) { faq in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(faq.0)
                            .font(.subheadline.weight(.semibold))
                        Text(faq.1)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Giving FAQ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct GivingDisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Donation Disclaimer")
                        .font(.title2.bold())

                    Text("AMEN facilitates connections between donors and verified nonprofit organizations. AMEN is not itself a charitable organization and does not hold or redirect funds.")

                    Text("All donations are made directly to the recipient organization. AMEN charges a platform fee of up to 2.9% + $0.30 per transaction to cover payment processing costs. You may elect to cover this fee so the organization receives 100% of your intended gift.")

                    Text("Tax deductibility depends on your jurisdiction and the recipient organization's status. Always consult a qualified tax advisor for guidance specific to your situation.")

                    Text("For questions or concerns about a specific organization, contact support@amenapp.com.")
                }
                .font(.callout)
                .padding()
            }
            .navigationTitle("Disclaimer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
