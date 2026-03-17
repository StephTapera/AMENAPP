//
//  ChurchNotesShareHelper.swift
//  AMENAPP
//
//  Helper for sharing and exporting church notes
//

import SwiftUI
import PDFKit
import FirebaseAuth

struct ChurchNotesShareHelper {
    
    /// Share note using UIActivityViewController
    static func shareNote(_ note: ChurchNote, from view: UIView?) {
        // P0 FIX: Use the stateless generateShareText helper directly — do NOT
        // instantiate a bare ChurchNotesService() here; that object has no auth
        // context and its notes array is empty, which caused exportAllNotes()
        // to silently produce empty exports.
        let shareText = generateShareText(for: note)
        
        let activityVC = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        // Exclude certain activity types if needed
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact
        ]
        
        // Present from window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            
            // For iPad: set popover presentation
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = view ?? rootVC.view
                popover.sourceRect = view?.bounds ?? rootVC.view.bounds
            }
            
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Share Text Generation

    /// Generate shareable text from a note without requiring a live service instance.
    /// P0 FIX: The previous code created ChurchNotesService() here which had no auth context
    /// and an empty notes array, making exportAllNotes() produce a blank export.
    static func generateShareText(for note: ChurchNote) -> String {
        var text = "📖 \(note.title)\n\n"
        if let sermonTitle = note.sermonTitle { text += "Sermon: \(sermonTitle)\n" }
        if let pastor = note.pastor          { text += "Pastor: \(pastor)\n" }
        if let churchName = note.churchName  { text += "Church: \(churchName)\n" }
        text += "Date: \(note.date.formatted(date: .long, time: .omitted))\n"
        if !note.scriptureReferences.isEmpty {
            text += "Scripture: \(note.scriptureReferences.joined(separator: ", "))\n"
        }
        text += "\n---\n\n\(note.content)"
        if !note.tags.isEmpty {
            text += "\n\n🏷️ Tags: \(note.tags.joined(separator: ", "))"
        }
        text += "\n\n✨ Shared from AMEN App"
        return text
    }

    /// Export a collection of notes to a single text block.
    static func exportNotes(_ notes: [ChurchNote]) -> String {
        var out = "🙏 Church Notes from AMEN\n"
        out += "Exported: \(Date().formatted(date: .long, time: .shortened))\n"
        out += "Total Notes: \(notes.count)\n\n"
        out += String(repeating: "=", count: 50) + "\n\n"
        for (i, note) in notes.enumerated() {
            out += "[\(i + 1)] \(generateShareText(for: note))\n\n"
            out += String(repeating: "-", count: 50) + "\n\n"
        }
        return out
    }

    /// Generate PDF from note
    static func generatePDF(for note: ChurchNote) -> Data? {
        let pdfMetaData = [
            kCGPDFContextCreator: "AMEN App",
            kCGPDFContextAuthor: "Church Notes",
            kCGPDFContextTitle: note.title
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yPosition: CGFloat = 50
            let margin: CGFloat = 50
            let contentWidth = pageRect.width - (2 * margin)
            
            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let titleString = note.title as NSString
            let titleRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: 40)
            titleString.draw(in: titleRect, withAttributes: titleAttributes)
            yPosition += 50
            
            // Metadata
            let metadataFont = UIFont.systemFont(ofSize: 12, weight: .regular)
            let metadataColor = UIColor.darkGray
            
            if let sermonTitle = note.sermonTitle {
                drawText("Sermon: \(sermonTitle)", at: &yPosition, margin: margin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            if let pastor = note.pastor {
                drawText("Pastor: \(pastor)", at: &yPosition, margin: margin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            if let churchName = note.churchName {
                drawText("Church: \(churchName)", at: &yPosition, margin: margin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            let dateString = "Date: \(note.date.formatted(date: .long, time: .omitted))"
            drawText(dateString, at: &yPosition, margin: margin, width: contentWidth, font: metadataFont, color: metadataColor)
            
            if !note.scriptureReferences.isEmpty {
                drawText("Scripture: \(note.scriptureReferences.joined(separator: ", "))", at: &yPosition, margin: margin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            yPosition += 20
            
            // Divider
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.move(to: CGPoint(x: margin, y: yPosition))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition))
            context.cgContext.strokePath()
            yPosition += 20
            
            // Content
            let contentAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.black
            ]
            let contentString = note.content as NSString
            let contentRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: pageRect.height - yPosition - margin)
            contentString.draw(in: contentRect, withAttributes: contentAttributes)
            
            // Footer
            let footerY = pageRect.height - 30
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.gray
            ]
            let footerString = "Generated by AMEN App - \(Date().formatted(date: .abbreviated, time: .shortened))" as NSString
            let footerRect = CGRect(x: margin, y: footerY, width: contentWidth, height: 20)
            footerString.draw(in: footerRect, withAttributes: footerAttributes)
        }
        
        return data
    }
    
    private static func drawText(_ text: String, at yPosition: inout CGFloat, margin: CGFloat, width: CGFloat, font: UIFont, color: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let string = text as NSString
        let rect = CGRect(x: margin, y: yPosition, width: width, height: 20)
        string.draw(in: rect, withAttributes: attributes)
        yPosition += 25
    }
    
    /// Share PDF of note
    static func sharePDF(for note: ChurchNote, from view: UIView?) {
        guard let pdfData = generatePDF(for: note) else {
            dlog("Failed to generate PDF")
            return
        }
        
        // Save PDF to temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(note.title.replacingOccurrences(of: " ", with: "_")).pdf"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try pdfData.write(to: fileURL)
            
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = view ?? rootVC.view
                    popover.sourceRect = view?.bounds ?? rootVC.view.bounds
                }
                
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            dlog("Error saving PDF: \(error)")
        }
    }
    
    /// Export all notes as text file
    static func exportAllNotes(_ notes: [ChurchNote], from view: UIView?) {
        // P0 FIX: Use the passed-in notes array directly via the static helper.
        let exportText = exportNotes(notes)
        
        // Save to temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "AMEN_Church_Notes_\(Date().formatted(date: .abbreviated, time: .omitted)).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try exportText.write(to: fileURL, atomically: true, encoding: .utf8)
            
            let activityVC = UIActivityViewController(
                activityItems: [fileURL],
                applicationActivities: nil
            )
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = view ?? rootVC.view
                    popover.sourceRect = view?.bounds ?? rootVC.view.bounds
                }
                
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            dlog("Error exporting notes: \(error)")
        }
    }
    
    /// Share to community (posts note to community feed)
    static func shareToCommunit(_ note: ChurchNote, completion: @escaping (Bool) -> Void) {
        guard FirebaseManager.shared.currentUser?.uid != nil else {
            completion(false)
            return
        }
        
        Task {
            do {
                // Create post content from note
                var postContent = "📖 \(note.title)\n\n"
                if let sermonTitle = note.sermonTitle {
                    postContent += "Sermon: \(sermonTitle)\n"
                }
                if let pastor = note.pastor {
                    postContent += "Pastor: \(pastor)\n"
                }
                if let churchName = note.churchName {
                    postContent += "Church: \(churchName)\n"
                }
                if !note.scriptureReferences.isEmpty {
                    postContent += "Scripture: \(note.scriptureReferences.joined(separator: ", "))\n"
                }
                postContent += "\n\(note.content)"
                
                // Create post using PostsManager with churchNoteId
                await MainActor.run {
                    PostsManager.shared.createPost(
                        content: postContent,
                        category: .openTable,
                        topicTag: "Church Notes",
                        visibility: .everyone,
                        allowComments: true,
                        imageURLs: nil,
                        linkURL: nil,
                        churchNoteId: note.id
                    )
                }
                
                dlog("✅ Church note shared to community successfully")
                completion(true)
            }
        }
    }
}
