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
    @Published var selectedPlanID = MemberDisplayConfig.defaultSelectedPlanID

    /// 促销倒计时剩余秒数，页面可见期间从 1 小时本地递减，不持久化
    @Published private(set) var promotionRemainingSeconds: Int = MemberDisplayConfig.promotionDuration

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
                if self.promotionRemainingSeconds > 0 {
                    self.promotionRemainingSeconds -= 1
                }
            }
        }
    }

    /// 页面消失时取消倒计时
    func stopPromotionCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    /// 促销倒计时展示文本，始终输出两位小时、分钟和秒。
    var formattedPromotionCountdown: String {
        let hours = promotionRemainingSeconds / 3_600
        let minutes = (promotionRemainingSeconds % 3_600) / 60
        let seconds = promotionRemainingSeconds % 60
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
            hasLoaded = true
            loadState = (content.backgroundPosters.isEmpty && content.memberOnlyDramas.isEmpty) ? .empty : .loaded
        } catch {
            // 静态套餐和权益仍可浏览，仅真实剧集区显示错误
            loadState = .failed(error.localizedDescription)
            Logger.viewModel.error("MemberViewModel loadContent failed: \(error)")
        }
    }
}
