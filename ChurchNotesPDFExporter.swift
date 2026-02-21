//
//  ChurchNotesPDFExporter.swift
//  AMENAPP
//
//  PDF export functionality for Church Notes
//

import Foundation
import UIKit
import PDFKit

class ChurchNotesPDFExporter {
    static let shared = ChurchNotesPDFExporter()
    
    private init() {}
    
    /// Export a single church note to PDF
    func exportToPDF(_ note: ChurchNote) throws -> URL {
        let pdfData = try generatePDFData(for: note)
        
        // Save to temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(note.title.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).pdf"
        let fileURL = tempDir.appendingPathComponent(filename)
        
        try pdfData.write(to: fileURL)
        
        return fileURL
    }
    
    /// Export multiple notes to a single PDF
    func exportMultipleNotes(_ notes: [ChurchNote]) throws -> URL {
        let pdfData = try generatePDFData(for: notes)
        
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "ChurchNotes_\(Date().timeIntervalSince1970).pdf"
        let fileURL = tempDir.appendingPathComponent(filename)
        
        try pdfData.write(to: fileURL)
        
        return fileURL
    }
    
    // MARK: - PDF Generation
    
    private func generatePDFData(for note: ChurchNote) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            var yOffset: CGFloat = 40
            let leftMargin: CGFloat = 40
            let rightMargin: CGFloat = pageRect.width - 40
            let contentWidth = rightMargin - leftMargin
            
            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let titleString = note.title as NSString
            let titleSize = titleString.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: titleAttributes,
                context: nil
            )
            titleString.draw(
                in: CGRect(x: leftMargin, y: yOffset, width: contentWidth, height: titleSize.height),
                withAttributes: titleAttributes
            )
            yOffset += titleSize.height + 20
            
            // Metadata
            let metadataFont = UIFont.systemFont(ofSize: 12)
            let metadataColor = UIColor.gray
            
            if let sermonTitle = note.sermonTitle {
                yOffset = drawText("Sermon: \(sermonTitle)", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            if let churchName = note.churchName {
                yOffset = drawText("Church: \(churchName)", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            if let pastor = note.pastor {
                yOffset = drawText("Pastor: \(pastor)", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            yOffset = drawText("Date: \(dateFormatter.string(from: note.date))", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
            
            if let scripture = note.scripture, !scripture.isEmpty {
                yOffset = drawText("Scripture: \(scripture)", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            yOffset += 20
            
            // Divider
            let dividerPath = UIBezierPath()
            dividerPath.move(to: CGPoint(x: leftMargin, y: yOffset))
            dividerPath.addLine(to: CGPoint(x: rightMargin, y: yOffset))
            UIColor.lightGray.setStroke()
            dividerPath.lineWidth = 0.5
            dividerPath.stroke()
            yOffset += 20
            
            // Content
            let contentFont = UIFont.systemFont(ofSize: 14)
            let contentColor = UIColor.black
            
            let paragraphs = note.content.components(separatedBy: "\n\n")
            for paragraph in paragraphs {
                if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    yOffset = drawText(paragraph, at: yOffset, leftMargin: leftMargin, width: contentWidth, font: contentFont, color: contentColor)
                    yOffset += 10
                    
                    // Start new page if needed
                    if yOffset > pageRect.height - 100 {
                        context.beginPage()
                        yOffset = 40
                    }
                }
            }
            
            // Tags
            if !note.tags.isEmpty {
                yOffset += 20
                let tagsText = "Tags: " + note.tags.joined(separator: ", ")
                yOffset = drawText(tagsText, at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
            }
            
            // Footer
            yOffset = pageRect.height - 60
            let footerText = "Generated by AMEN App • \(Date().formatted(date: .long, time: .shortened))"
            drawText(footerText, at: yOffset, leftMargin: leftMargin, width: contentWidth, font: UIFont.systemFont(ofSize: 10), color: UIColor.lightGray, alignment: .center)
        }
        
        return data
    }
    
    private func generatePDFData(for notes: [ChurchNote]) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let data = renderer.pdfData { context in
            for (index, note) in notes.enumerated() {
                if index > 0 {
                    context.beginPage() // New page for each note
                }
                
                var yOffset: CGFloat = 40
                let leftMargin: CGFloat = 40
                let rightMargin: CGFloat = pageRect.width - 40
                let contentWidth = rightMargin - leftMargin
                
                // Note number
                let noteNumberText = "Note \(index + 1) of \(notes.count)"
                yOffset = drawText(noteNumberText, at: yOffset, leftMargin: leftMargin, width: contentWidth, font: UIFont.systemFont(ofSize: 10), color: UIColor.gray, alignment: .right)
                yOffset += 10
                
                // Title
                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                let titleString = note.title as NSString
                let titleSize = titleString.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: titleAttributes,
                    context: nil
                )
                titleString.draw(
                    in: CGRect(x: leftMargin, y: yOffset, width: contentWidth, height: titleSize.height),
                    withAttributes: titleAttributes
                )
                yOffset += titleSize.height + 15
                
                // Metadata (condensed for multi-note export)
                let metadataFont = UIFont.systemFont(ofSize: 11)
                let metadataColor = UIColor.gray
                
                var metadataItems: [String] = []
                if let sermonTitle = note.sermonTitle {
                    metadataItems.append(sermonTitle)
                }
                if let pastor = note.pastor {
                    metadataItems.append(pastor)
                }
                if !metadataItems.isEmpty {
                    yOffset = drawText(metadataItems.joined(separator: " • "), at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
                }
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .medium
                yOffset = drawText(dateFormatter.string(from: note.date), at: yOffset, leftMargin: leftMargin, width: contentWidth, font: metadataFont, color: metadataColor)
                
                yOffset += 15
                
                // Content (truncated for multi-note)
                let contentFont = UIFont.systemFont(ofSize: 12)
                let truncatedContent = String(note.content.prefix(500))
                yOffset = drawText(truncatedContent + (note.content.count > 500 ? "..." : ""), at: yOffset, leftMargin: leftMargin, width: contentWidth, font: contentFont, color: UIColor.black)
            }
            
            // Cover page
            context.beginPage()
            var yOffset: CGFloat = pageRect.height / 3
            let leftMargin: CGFloat = 40
            let contentWidth = pageRect.width - 80
            
            drawText("Church Notes Collection", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: UIFont.systemFont(ofSize: 32, weight: .bold), color: UIColor.black, alignment: .center)
            yOffset += 60
            
            drawText("\(notes.count) Notes", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: UIFont.systemFont(ofSize: 20), color: UIColor.gray, alignment: .center)
            yOffset += 40
            
            drawText("Exported from AMEN App", at: yOffset, leftMargin: leftMargin, width: contentWidth, font: UIFont.systemFont(ofSize: 14), color: UIColor.lightGray, alignment: .center)
            yOffset += 20
            
            drawText(Date().formatted(date: .long, time: .shortened), at: yOffset, leftMargin: leftMargin, width: contentWidth, font: UIFont.systemFont(ofSize: 12), color: UIColor.lightGray, alignment: .center)
        }
        
        return data
    }
    
    // MARK: - Helper Methods
    
    @discardableResult
    private func drawText(_ text: String, at yOffset: CGFloat, leftMargin: CGFloat, width: CGFloat, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) -> CGFloat {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineSpacing = 2
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        
        attributedString.draw(in: CGRect(x: leftMargin, y: yOffset, width: width, height: textSize.height))
        
        return yOffset + textSize.height + 5
    }
}

// MARK: - Share Extension

extension ChurchNote {
    /// Generate a shareable PDF URL for this note
    func generatePDF() throws -> URL {
        try ChurchNotesPDFExporter.shared.exportToPDF(self)
    }
}
