import Foundation
import SwiftUI

// MARK: - VIP ViewModel
@MainActor
final class VIPViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedPlanId: String = "yearly"
    @Published var plans: [VIPPlan] = []
    @Published var benefits: [VIPBenefit] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies

    private let repository: VIPRepositoryProtocol

    // MARK: - Init

    init(repository: VIPRepositoryProtocol) {
        self.repository = repository
        Task { await loadData() }
    }

    // MARK: - Public Helpers

    var selectedPlan: VIPPlan? {
        plans.first { $0.id == selectedPlanId }
    }

    func formattedExpiryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    func remainingDays(from date: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        return max(days, 0)
    }

    // MARK: - Data Loading

    func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            plans = try await repository.fetchPlans()
        } catch {
            errorMessage = L10n.membershipLoadFailed
            logError("VIPViewModel.fetchPlans failed: \(error)")
        }

        do {
            benefits = try await repository.fetchBenefits()
        } catch {
            logError("VIPViewModel.fetchBenefits failed: \(error)")
        }
    }

    private func logError(_ message: String) {
        #if DEBUG
        Logger.viewModel.error("\(message)")
        #endif
    }
}
