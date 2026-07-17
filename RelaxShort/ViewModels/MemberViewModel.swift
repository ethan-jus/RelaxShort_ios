import SwiftUI

// MARK: - Member ViewModel

/// Member 订阅页 ViewModel。
/// 管理页面加载状态、真实内容数据和 UI 展示状态。
/// 页面首次可见时加载真实数据，Tab 常驻期间避免重复请求。
@MainActor
final class MemberViewModel: ObservableObject {

    // MARK: - Load State

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    // MARK: - Published Properties

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var backgroundPosters: [DramaItem] = []
    @Published private(set) var memberOnlyDramas: [DramaItem] = []
    @Published private(set) var plans: [MemberPlanDisplayOption] = []
    @Published private(set) var benefits: [MemberBenefitDisplayItem] = []
    @Published private(set) var legalLinks: MemberLegalLinks?
    @Published var selectedPlanID = MemberDisplayConfig.defaultSelectedPlanID

    /// 当前时间只用于计算服务端促销窗口倒计时，不创建本地活动。
    @Published private(set) var currentDate = Date()

    // MARK: - Dependencies

    private let repository: MemberRepositoryProtocol

    /// 是否已成功加载过数据（Tab 常驻期间避免重复请求）
    private var hasLoaded = false
    /// 倒计时 Timer
    private var countdownTask: Task<Void, Never>?

    // MARK: - Init

    init(repository: MemberRepositoryProtocol = RealMemberRepository()) {
        self.repository = repository
    }

    // MARK: - Public Methods

    /// 页面可见时调用。首次加载真实数据，后续跳过。
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        Task { await loadContent() }
    }

    /// 用户主动重试（失败后可用）
    func retry() {
        Task { await loadContent() }
    }

    /// 页面出现时启动促销倒计时
    func startPromotionCountdown() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { break }
                self.currentDate = Date()
            }
        }
    }

    /// 页面消失时取消倒计时
    func stopPromotionCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// 促销倒计时展示文本，活动过期后返回 nil。
    func formattedPromotionCountdown(
        for promotion: MemberPromotion
    ) -> String? {
        let remaining = Int(
            promotion.endsAt.timeIntervalSince(currentDate)
        )
        guard remaining > 0 else { return nil }
        let hours = remaining / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    // MARK: - Private

    private func loadContent() async {
        loadState = .loading
        do {
            let content = try await repository.fetchMemberContent(
                contentLanguage: nil,  // 由 APIClient headers 自动携带
                countryCode: nil
            )
            backgroundPosters = content.backgroundPosters
            memberOnlyDramas = content.memberOnlyDramas
            // 服务端可售目录是唯一依据；空数组表示当前没有可售套餐。
            plans = content.plans
            benefits = content.benefits
            legalLinks = content.legalLinks
            if !plans.contains(where: { $0.id == selectedPlanID }) {
                selectedPlanID = plans.first?.id
                    ?? MemberDisplayConfig.defaultSelectedPlanID
            }
            hasLoaded = true
            loadState = (content.backgroundPosters.isEmpty && content.memberOnlyDramas.isEmpty) ? .empty : .loaded
        } catch {
            plans = []
            benefits = []
            legalLinks = nil
            loadState = .failed(error.localizedDescription)
            Logger.viewModel.error("MemberViewModel loadContent failed: \(error)")
        }
    }
}
