// AudioPreferencesView.swift
// AMEN App — Accessibility Intelligence Layer (Phase 3)
//
// Settings sub-view: playback rate picker, voice locale,
// pause between posts toggle. Stored in UserDefaults only (no Firestore).

import SwiftUI

struct AudioPreferencesView: View {

    @AppStorage("amen.audio.listenEnabled") private var listenEnabled: Bool = false
    @AppStorage("amen.audio.defaultRate") private var defaultRate: Double = 1.0
    @AppStorage("amen.audio.pauseBetweenPosts") private var pauseBetweenPosts: Bool = true
    @AppStorage("amen.audio.narrateTranslated") private var narrateTranslated: Bool = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $listenEnabled) {
                    Text("Enable Listen Button")
                        .font(AMENFont.regular(15))
                }
            } header: {
                Text("Audio Narration")
            } footer: {
                Text("When enabled, a Listen button appears on posts so you can hear them read aloud.")
            }

            Section {
                HStack {
                    Text("Default Speed")
                        .font(AMENFont.regular(15))
                    Spacer()
                    Picker("Speed", selection: $defaultRate) {
                        Text("0.5x").tag(0.5)
                        Text("0.75x").tag(0.75)
                        Text("1x").tag(1.0)
                        Text("1.25x").tag(1.25)
                        Text("1.5x").tag(1.5)
                        Text("2x").tag(2.0)
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Playback")
            } footer: {
                Text("Speed setting applies to new playback sessions")
            }

            Section {
                Toggle(isOn: $narrateTranslated) {
                    Text("Read translated version")
                        .font(AMENFont.regular(15))
                }
            } header: {
                Text("Narration Language")
            } footer: {
                Text("When a post is translated, read the translation instead of the original text. Uses a voice matching the translated language.")
            }

            Section {
                Toggle(isOn: $pauseBetweenPosts) {
                    Text("Pause Between Posts")
                        .font(AMENFont.regular(15))
                }
            } footer: {
                Text("Add a brief pause when moving to the next post in the queue")
            }

            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color(.tertiaryLabel))
                    Text("Audio uses your device's built-in text-to-speech. Voice quality depends on your device settings.")
                        .font(AMENFont.regular(13))
                        .foregroundStyle(Color(.secondaryLabel))
                }
            }
        }
        .navigationTitle("Audio Narration")
        .navigationBarTitleDisplayMode(.inline)
    }
}
