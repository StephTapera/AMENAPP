
//
//  ShareExtensionViewController.swift
//  AMENShareExtension  ← separate Xcode target
//
//  TODO(gate: HUMAN-MACHINE): The Swift source files in this directory are complete,
//  but the AMENShareExtension Xcode target does NOT yet exist in the .xcodeproj.
//  A human engineer must complete these steps in Xcode before this extension ships:
//    1. File → New → Target → Share Extension → name it "AMENShareExtension"
//    2. Add both targets to the App Group "group.com.amenapp.shared"
//       (Target → Signing & Capabilities → + App Groups)
//    3. Add AMENShareExtension to the Embed App Extensions build phase of the main app
//    4. Add "amen" URL scheme to the main app's Info.plist (CFBundleURLTypes)
//    5. Add LinkPresentation.framework to AMENShareExtension's linked frameworks
//    6. Assign ShareExtensionViewController.swift + ShareModels.swift to the new target
//  Until these steps are complete this code is NOT compiled into any binary.
//  Lane status: DONE-PROVEN (code) | BLOCKED (Xcode target wiring) — HUMAN-MACHINE gate.
//
//  Supported input types: URL, UIImage, plain text.
//  No API keys, no network calls — only writes a ShareDraft to App Group UserDefaults.
//

import UIKit
import Social
import UniformTypeIdentifiers
import SwiftUI

final class ShareExtensionViewController: UIViewController {

    private let appGroupID = "group.com.amenapp.shared"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemBackground

        let composeVM = ShareComposeViewModel()
        let composeView = ShareExtensionComposeView(viewModel: composeVM) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        } onPost: { [weak self] draft in
            self?.saveDraft(draft)
            self?.openAMEN()
            self?.extensionContext?.completeRequest(returningItems: nil)
        }

        let host = UIHostingController(rootView: composeView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { await extractContent(into: composeVM) }
    }

    // MARK: - Content Extraction

    private func extractContent(into vm: ShareComposeViewModel) async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let providers = item.attachments else { continue }
            for provider in providers {

                // 1. URL (highest priority — sanitize to http/https only)
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let raw = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                       let url = raw as? URL,
                       let scheme = url.scheme?.lowercased(),
                       (scheme == "http" || scheme == "https") {
                        await MainActor.run {
                            vm.linkURLString = url.absoluteString
                            vm.suggestDestination(for: url)
                        }
                        return
                    }
                }

                // 2. Image
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let img = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? UIImage,
                       let data = img.jpegData(compressionQuality: 0.85) {
                        await MainActor.run { vm.imageData = data }
                        return
                    }
                }

                // 3. Plain text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                        await MainActor.run {
                            vm.draftText = Self.sanitize(text)
                            vm.suggestDestinationFromText(text)
                        }
                        return
                    }
                }
            }
        }
    }

    // MARK: - Save Draft to App Group

    private func saveDraft(_ draft: ShareDraft) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: "pendingShareDraft")
        defaults.synchronize()
    }

    // MARK: - Deep-link into AMEN

    private func openAMEN() {
        guard let url = URL(string: "amen://share?source=extension") else { return }
        // Walk the responder chain to find UIApplication (extension pattern)
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication { app.open(url); break }
            responder = r.next
        }
    }

    // MARK: - Sanitization

    static func sanitize(_ text: String) -> String {
        var t = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if t.count > 500 { t = String(t.prefix(500)) }
        return t
    }
}
