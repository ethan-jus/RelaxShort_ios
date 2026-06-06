import SwiftUI

// MARK: - Membership ViewModel
/// 会员购买页 ViewModel
/// 管理会员选项、选中态和购买逻辑
@MainActor
final class MembershipViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedOptionIndex: Int = 0
    @Published var options: [MembershipOption] = []

    // MARK: - Init

    init() {
        loadOptions()
    }

    // MARK: - Computed

    var selectedOption: MembershipOption? {
        guard selectedOptionIndex >= 0, selectedOptionIndex < options.count else { return nil }
        return options[selectedOptionIndex]
    }

    // MARK: - Public Methods

    func selectOption(at index: Int) {
        guard index >= 0, index < options.count else { return }
        selectedOptionIndex = index
    }

    /// 执行购买（预留接入点）
    func purchase() {
        // TODO: 接入真实购买流程
        #if DEBUG
        let title = self.options[self.selectedOptionIndex].title
        Logger.viewModel.notice("MembershipViewModel Purchase: \(title)")
        #endif
    }

    // MARK: - Private

    private func loadOptions() {
        options = [
            MembershipOption(
                title: "周会员",
                price: "$12.99",
                originalPrice: "$19.99",
                detail: "前3周$12.99/周，然后$19.99/周",
                isSelected: true,
                discountCountdown: "00:18:54"
            ),
            MembershipOption(
                title: "月会员",
                price: "$39.99",
                originalPrice: nil,
                detail: "$39.99/月",
                isSelected: false,
                discountCountdown: nil
            ),
            MembershipOption(
                title: "年会员",
                price: "$149.99",
                originalPrice: nil,
                detail: "$149.99/年",
                isSelected: false,
                discountCountdown: nil
            )
        ]
    }
}
