// StewardshipViewModel.swift
// AMENAPP
//
// Stewardship dashboard — formative, not addictive.
// Income stays on-device. Annual review from Firestore (no income stored server-side).

import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
final class StewardshipViewModel: ObservableObject {

    @Published var annualReview: GivingAnnualReview? = nil
    @Published var isLoadingReview = false
    @Published var showIncomeInput = false
    @Published var incomeInputText = ""
    @Published var tithingPercentText = "10"
    @Published var activeSection: StewardshiSection? = nil
    @Published var selectedReceiptYear = Calendar.current.component(.year, from: Date())

    let store: StewardshipLocalStore
    private let dataService = NonprofitDataService()

    init(store: StewardshipLocalStore) {
        self.store = store
    }

    enum StewardshiSection: String, Identifiable {
        case planner = "Monthly Planner"
        case allocation = "Allocation"
        case recurring = "Recurring Gifts"
        case taxCenter = "Tax Center"
        case journal = "Giving Journal"
        case annualReview = "Annual Review"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .planner: return "chart.pie.fill"
            case .allocation: return "chart.bar.fill"
            case .recurring: return "arrow.clockwise"
            case .taxCenter: return "doc.text.fill"
            case .journal: return "book.closed.fill"
            case .annualReview: return "calendar.badge.checkmark"
            }
        }
    }

    func onAppear() {
        Task { await loadAnnualReview() }
        loadIncomeFromStore()
    }

    private func loadIncomeFromStore() {
        if let income = store.snapshot.monthlyIncomeEstimate {
            incomeInputText = "\(income / 100)"
        }
        if let pct = store.snapshot.tithingTargetPercent {
            tithingPercentText = "\(Int(pct * 100))"
        }
    }

    private func loadAnnualReview() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let year = Calendar.current.component(.year, from: Date())
        isLoadingReview = true
        annualReview = try? await dataService.fetchAnnualReview(userId: userId, year: year)
        isLoadingReview = false
    }

    func saveIncome() {
        let cents = (Int(incomeInputText) ?? 0) * 100
        store.saveIncomeEstimate(cents > 0 ? cents : nil)
        showIncomeInput = false
    }

    func saveTithing() {
        let pct = (Double(tithingPercentText) ?? 10.0) / 100.0
        store.saveTithingTarget(pct)
    }

    var monthlyTithingTarget: String? {
        store.snapshot.tithingTargetFormatted
    }

    var hasIncomeSet: Bool {
        store.snapshot.monthlyIncomeEstimate != nil
    }

    var receiptsForSelectedYear: [GivingReceipt] {
        store.receipts(forYear: selectedReceiptYear)
    }

    var availableReceiptYears: [Int] {
        let years = Set(store.receipts.compactMap { $0.taxYear })
        let current = Calendar.current.component(.year, from: Date())
        var result = Array(years).sorted(by: >)
        if !result.contains(current) { result.insert(current, at: 0) }
        return result
    }
}
