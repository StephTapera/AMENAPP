//
//  PrayForRequestIntent.swift
//  AMENWidgetExtension
//
//  Live Activity intent for the "🙏 I'm praying" button (iOS 17+).
//  Runs in the widget extension process — calls the prayForRequest Cloud
//  Function via URLSession using uid + App Check token cached in the
//  shared App Group by the host app.
//

import AppIntents
import ActivityKit

@available(iOS 17.0, *)
struct PrayForRequestIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark Praying"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Request ID")
    var requestId: String

    init() { self.requestId = "" }
    init(requestId: String) { self.requestId = requestId }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: "group.com.amenapp.shared")
        guard let uid = defaults?.string(forKey: "currentUserUid"), !uid.isEmpty else {
            return .result()
        }
        let appCheckToken = defaults?.string(forKey: "cachedAppCheckToken") ?? ""

        guard let url = URL(string: "https://us-central1-amen-5e359.cloudfunctions.net/prayForRequest") else {
            return .result()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !appCheckToken.isEmpty {
            request.setValue(appCheckToken, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        let body: [String: Any] = ["data": ["requestId": requestId, "uid": uid]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        _ = try? await URLSession.shared.data(for: request)
        return .result()
    }
}
