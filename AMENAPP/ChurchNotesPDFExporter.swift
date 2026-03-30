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

// MARK: - Feature 9: Markdown, Clean Text, and Devotional Card Exports

extension ChurchNotesPDFExporter {

    // MARK: - Markdown Export

    /// Renders a church note as a Markdown string suitable for pasting into
    /// Notion, Obsidian, Bear, or any Markdown-capable app.
    func exportAsMarkdown(note: ChurchNote) -> String {
        var md = ""

        // Frontmatter block
        md += "# \(note.title)\n\n"

        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none

        var meta: [(String, String)] = []
        if let s = note.sermonTitle, !s.isEmpty  { meta.append(("Sermon",   s)) }
        if let c = note.churchName,  !c.isEmpty  { meta.append(("Church",   c)) }
        if let p = note.pastor,      !p.isEmpty  { meta.append(("Pastor",   p)) }
        meta.append(("Date", df.string(from: note.date)))
        if let ref = note.scripture, !ref.isEmpty { meta.append(("Scripture", ref)) }

        if !meta.isEmpty {
            md += "| Field | Value |\n"
            md += "|---|---|\n"
            for (k, v) in meta { md += "| **\(k)** | \(v) |\n" }
            md += "\n"
        }

        // Scripture references
        if !note.scriptureReferences.isEmpty {
            md += "## Scripture References\n"
            for ref in note.scriptureReferences { md += "- \(ref)\n" }
            md += "\n"
        }

        // Key points
        if !note.keyPoints.isEmpty {
            md += "## Key Points\n"
            for kp in note.keyPoints { md += "- \(kp)\n" }
            md += "\n"
        }

        // Main content
        md += "## Notes\n\n"
        md += note.content
        md += "\n\n"

        // Tags
        let allTags = (note.tags + note.claudeTags).map({ "#\($0)" })
        if !allTags.isEmpty {
            md += "---\n"
            md += allTags.joined(separator: " ")
            md += "\n"
        }

        md += "\n> *Exported from AMEN App — \(Date().formatted(date: .abbreviated, time: .omitted))*\n"
        return md
    }

    // MARK: - Clean Text Export

    /// Returns a plain-text version suitable for copying into email or SMS.
    func exportCleanText(note: ChurchNote) -> String {
        var lines: [String] = []

        lines.append(note.title.uppercased())
        lines.append(String(repeating: "─", count: min(note.title.count, 40)))

        let df = DateFormatter(); df.dateStyle = .medium
        var meta: [String] = [df.string(from: note.date)]
        if let c = note.churchName { meta.append(c) }
        if let p = note.pastor     { meta.append(p) }
        lines.append(meta.joined(separator: " · "))

        if let ref = note.scripture, !ref.isEmpty {
            lines.append("Scripture: \(ref)")
        }
        lines.append("")

        if !note.keyPoints.isEmpty {
            lines.append("KEY POINTS")
            for kp in note.keyPoints { lines.append("  • \(kp)") }
            lines.append("")
        }

        lines.append("NOTES")
        lines.append(note.content)

        if !note.tags.isEmpty {
            lines.append("")
            lines.append("Tags: " + note.tags.joined(separator: ", "))
        }

        lines.append("")
        lines.append("Exported from AMEN App")
        return lines.joined(separator: "\n")
    }

    // MARK: - Devotional Card Export

    /// Renders a 1080×1080 pt stylised devotional card image.
    /// Contains: title, key scripture, first key point, church name, and date.
    func exportAsDevotionalCard(note: ChurchNote) -> UIImage {
        let size   = CGSize(width: 1080, height: 1080)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            // --- Background gradient ---
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.06, green: 0.04, blue: 0.12, alpha: 1).cgColor,
                    UIColor(red: 0.14, green: 0.08, blue: 0.24, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end:   CGPoint(x: size.width, y: size.height),
                options: []
            )

            // --- Gold accent line ---
            let gold = UIColor(red: 0.85, green: 0.68, blue: 0.27, alpha: 1)
            gold.setFill()
            ctx.fill(CGRect(x: 80, y: 80, width: 6, height: 200))

            // --- AMEN tag ---
            let tagAttrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: gold,
                .kern:            4.0
            ]
            ("AMEN" as NSString).draw(at: CGPoint(x: 108, y: 90), withAttributes: tagAttrs)

            // --- Title ---
            let titlePara = NSMutableParagraphStyle()
            titlePara.lineSpacing      = 8
            titlePara.lineBreakMode    = .byWordWrapping
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle:  titlePara
            ]
            let titleRect = CGRect(x: 80, y: 180, width: 920, height: 240)
            (note.title as NSString).draw(in: titleRect, withAttributes: titleAttrs)

            // --- Scripture reference ---
            let scriptureText = note.scripture ?? note.scriptureReferences.first ?? ""
            if !scriptureText.isEmpty {
                let scrAttrs: [NSAttributedString.Key: Any] = [
                    .font:            UIFont.systemFont(ofSize: 32, weight: .medium),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.75)
                ]
                (scriptureText as NSString).draw(at: CGPoint(x: 80, y: 440), withAttributes: scrAttrs)
            }

            // --- Horizontal divider ---
            UIColor.white.withAlphaComponent(0.15).setFill()
            ctx.fill(CGRect(x: 80, y: 510, width: 920, height: 1))

            // --- Key point ---
            let keyPoint = note.keyPoints.first ?? note.content.components(separatedBy: "\n")
                .first(where: { $0.count > 20 }) ?? ""
            if !keyPoint.isEmpty {
                let kpPara = NSMutableParagraphStyle()
                kpPara.lineSpacing   = 10
                kpPara.lineBreakMode = .byWordWrapping
                let kpAttrs: [NSAttributedString.Key: Any] = [
                    .font:           UIFont(name: "Georgia", size: 36) ?? .systemFont(ofSize: 36),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                    .paragraphStyle: kpPara
                ]
                let display = keyPoint.count > 160
                    ? String(keyPoint.prefix(157)) + "..."
                    : keyPoint
                (display as NSString).draw(
                    in: CGRect(x: 80, y: 540, width: 920, height: 300),
                    withAttributes: kpAttrs
                )
            }

            // --- Footer: church + date ---
            let df = DateFormatter(); df.dateStyle = .medium
            var footerParts: [String] = []
            if let c = note.churchName, !c.isEmpty { footerParts.append(c) }
            footerParts.append(df.string(from: note.date))
            let footerText = footerParts.joined(separator: "  ·  ")
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 26, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            (footerText as NSString).draw(at: CGPoint(x: 80, y: 960), withAttributes: footerAttrs)
        }
    }
}

// MARK: - Share Extension

extension ChurchNote {
    /// Generate a shareable PDF URL for this note
    func generatePDF() throws -> URL {
        try ChurchNotesPDFExporter.shared.exportToPDF(self)
    }
}
