import SwiftUI

// MARK: - Berean AI Helper Model Settings (System 27)
//
// Normal users see capability toggles in plain language.
// Advanced/debug mode not exposed here.

struct BereanGrokSettingsView: View {
    @ObservedObject private var flags = AMENFeatureFlags.shared
    @AppStorage("berean_helper_model_user_enabled")     private var helperEnabled = false
    @AppStorage("berean_external_context_user_enabled") private var externalEnabled = false
    @AppStorage("berean_show_provenance_labels")        private var provenanceLabels = false
    @AppStorage("berean_always_require_scripture")      private var alwaysScripture = false
    @AppStorage("berean_disable_public_context")        private var disablePublicContext = false

    var body: some View {
        List {
            Section {
                Toggle(isOn: helperBinding) {
                    settingRow(
                        icon: "sparkles",
                        title: "Use cost-efficient helper models",
                        detail: "Allows Amen to use a helper model for summarizing long questions, compressing context, and drafting study outlines. Final answers always go through Berean."
                    )
                }
                .disabled(!flags.bereanHelperModelEnabled)

                Toggle(isOn: externalBinding) {
                    settingRow(
                        icon: "globe",
                        title: "Allow external context summaries",
                        detail: "When you ask about public discussions or Christian debates, Amen can summarize what people are saying — clearly labeled as external context, not Scripture."
                    )
                }
                .disabled(!flags.bereanHelperExternalContextEnabled)
            } header: {
                Text("AI helper model")
            } footer: {
                Text("Helper models are used only for utility tasks — summarization, drafting, and context compression. They are never the final authority. All answers are Berean-verified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $provenanceLabels) {
                    settingRow(
                        icon: "tag",
                        title: "Show AI provenance labels",
                        detail: "Small chips below answers show whether Berean-checked, Scripture-grounded, or a helper model was used."
                    )
                }

                Toggle(isOn: $alwaysScripture) {
                    settingRow(
                        icon: "book.closed",
                        title: "Always require Scripture check",
                        detail: "Every Berean answer will include a Scripture-grounding pass, even for general questions."
                    )
                }

                Toggle(isOn: $disablePublicContext) {
                    settingRow(
                        icon: "person.2",
                        title: "Disable public-context mode",
                        detail: "Prevents Berean from summarizing public discussions. Only Scripture-grounded answers will be shown."
                    )
                }
            } header: {
                Text("Transparency")
            }

            Section {
                Text("Berean AI is a Bible study and reflection tool. It is not a replacement for your church community, pastoral care, or professional counseling. Helper model outputs are never presented as biblical teaching or pastoral authority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About Berean AI")
            }
        }
        .navigationTitle("Berean AI Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helperBinding: Binding<Bool> {
        Binding(
            get: { helperEnabled && flags.bereanHelperModelEnabled },
            set: { helperEnabled = $0 }
        )
    }

    private var externalBinding: Binding<Bool> {
        Binding(
            get: { externalEnabled && flags.bereanHelperExternalContextEnabled && !disablePublicContext },
            set: { externalEnabled = $0 }
        )
    }

    private func settingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.systemScaled(15))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
