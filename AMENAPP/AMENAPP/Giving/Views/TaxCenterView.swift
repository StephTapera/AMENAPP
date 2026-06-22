// TaxCenterView.swift
// AMENAPP
//
// Tax center — receipts by year, export, organization summary.
// No income data. No server storage of personal financial amounts.

import SwiftUI

struct TaxCenterView: View {
    @ObservedObject var store: StewardshipLocalStore
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var exportError: String?
    @State private var showExportError = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // Year picker
                    yearPicker

                    // Summary
                    if !receiptsForYear.isEmpty {
                        summaryCard
                    }

                    // Receipt list
                    receiptList
                }
                .padding(16)
                .padding(.bottom, 40)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Tax Center")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Export Failed", isPresented: $showExportError, actions: {
                Button("OK", role: .cancel) {}
            }, message: {
                Text(exportError ?? "Unable to prepare the CSV file.")
            })
        }
    }

    // MARK: - Year Picker

    private var yearPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableYears, id: \.self) { year in
                    Button {
                        withAnimation(.spring(duration: 0.22)) {
                            selectedYear = year
                        }
                    } label: {
                        Text(String(year))
                            .font(.systemScaled(14, weight: .medium))
                            .foregroundStyle(selectedYear == year ? AmenTheme.Colors.textInverse : AmenTheme.Colors.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(selectedYear == year
                                               ? AmenTheme.Colors.textPrimary
                                               : AmenTheme.Colors.backgroundSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(year))
                    .accessibilityHint(selectedYear == year ? "Selected tax year" : "Tap to view \(year) receipts")
                    .accessibilityAddTraits(selectedYear == year ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tax year \(selectedYear)")
                .font(.systemScaled(13, weight: .semibold))
                .foregroundStyle(AmenTheme.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(1.2)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total deductible")
                        .font(.systemScaled(11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text(totalForYear)
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Organizations")
                        .font(.systemScaled(11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("\(Set(receiptsForYear.map(\.destinationId)).count)")
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Receipts")
                        .font(.systemScaled(11))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("\(receiptsForYear.count)")
                        .font(.systemScaled(24, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textPrimary)
                }
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let csv = buildCSV()
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tax_export_\(selectedYear).csv")
                do {
                    try csv.write(to: tempURL, atomically: true, encoding: .utf8)
                    let ac = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .first?.windows.first?.rootViewController?
                        .present(ac, animated: true)
                } catch {
                    dlog("❌ Tax CSV export failed: \(error.localizedDescription)")
                    exportError = error.localizedDescription
                    showExportError = true
                }
            } label: {
                Label("Export \(selectedYear) receipts", systemImage: "square.and.arrow.up")
                    .font(.systemScaled(13, weight: .semibold))
                    .foregroundStyle(AmenTheme.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AmenTheme.Colors.backgroundSecondary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export \(selectedYear) tax receipts as CSV")
        }
        .padding(16)
        .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
        )
        .amenShadow(radius: 8, y: 3)
    }

    // MARK: - Receipt List

    private var receiptList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if receiptsForYear.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.systemScaled(36))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                    Text("No receipts for \(selectedYear)")
                        .font(.systemScaled(16, weight: .semibold))
                        .foregroundStyle(AmenTheme.Colors.textSecondary)
                    Text("Receipts will appear here after you give through AMEN-connected payment rails.")
                        .font(.systemScaled(14))
                        .foregroundStyle(AmenTheme.Colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(receiptsForYear.enumerated()), id: \.element.id) { idx, receipt in
                        TaxReceiptRow(receipt: receipt, onView: {
                            if let urlStr = receipt.receiptUrl, let url = URL(string: urlStr) {
                                UIApplication.shared.open(url)
                            }
                        })
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        if idx < receiptsForYear.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(AmenTheme.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(AmenTheme.Colors.borderSoft, lineWidth: 0.5)
                )
                .amenShadow(radius: 8, y: 3)
            }
        }
    }

    // MARK: - Computed

    private var receiptsForYear: [GivingReceipt] {
        store.receipts(forYear: selectedYear)
    }

    private var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        let fromReceipts = Set(store.receipts.map { $0.taxYear })
        var years = Array(fromReceipts).sorted(by: >)
        if !years.contains(current) { years.insert(current, at: 0) }
        return years
    }

    private var totalForYear: String {
        let total = receiptsForYear.reduce(0) { $0 + $1.amount }
        let dollars = Double(total) / 100.0
        return String(format: "$%.2f", dollars)
    }

    private func buildCSV() -> String {
        var lines = ["Date,Organization,Amount,Currency,Receipt URL"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        for receipt in receiptsForYear {
            let date = receipt.issuedAt.map { formatter.string(from: $0) } ?? ""
            let org = receipt.destinationName.replacingOccurrences(of: ",", with: " ")
            let amount = String(format: "%.2f", Double(receipt.amount) / 100.0)
            let currency = receipt.currency.uppercased()
            let url = receipt.receiptUrl ?? ""
            lines.append("\(date),\(org),\(amount),\(currency),\(url)")
        }
        return lines.joined(separator: "\n")
    }
}
