//
//  ShareSheet.swift
//  AMENAPP
//
//  Created by Steph on 1/19/26.
//

import SwiftUI
import UIKit

/// Reusable share sheet for sharing content via UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
