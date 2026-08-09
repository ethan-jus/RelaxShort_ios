import SwiftUI
import UIKit

// MARK: - Navigation Gesture

/// 在隐藏系统导航栏或系统返回按钮的二级页上恢复 iOS 原生屏幕边缘返回手势。
private struct InteractivePopGestureConfigurator:
    UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(
        context: Context
    ) -> GestureProbeViewController {
        GestureProbeViewController(isEnabled: isEnabled)
    }

    func updateUIViewController(
        _ controller: GestureProbeViewController,
        context: Context
    ) {
        controller.update(isEnabled: isEnabled)
    }

    static func dismantleUIViewController(
        _ controller: GestureProbeViewController,
        coordinator: Void
    ) {
        controller.restore()
    }

    final class GestureProbeViewController:
        UIViewController,
        UIGestureRecognizerDelegate {
        private var isGestureEnabled: Bool
        private var isPageVisible = false
        private weak var configuredNavigationController:
            UINavigationController?
        private weak var previousDelegate:
            (any UIGestureRecognizerDelegate)?
        private var ownsGestureDelegate = false

        init(isEnabled: Bool) {
            isGestureEnabled = isEnabled
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isPageVisible = true
            configureIfNeeded()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isPageVisible = false
            restore()
        }

        func update(isEnabled: Bool) {
            isGestureEnabled = isEnabled
            configureIfNeeded()
        }

        private func configureIfNeeded() {
            guard isPageVisible,
                  isGestureEnabled,
                  let navigationController,
                  let gesture =
                    navigationController.interactivePopGestureRecognizer else {
                restore()
                return
            }

            if configuredNavigationController !== navigationController {
                restore()
                configuredNavigationController = navigationController
            }

            if !ownsGestureDelegate {
                previousDelegate = gesture.delegate
                gesture.delegate = self
                ownsGestureDelegate = true
            }

            gesture.isEnabled =
                navigationController.viewControllers.count > 1
        }

        func restore() {
            guard ownsGestureDelegate,
                  let gesture =
                    configuredNavigationController?
                    .interactivePopGestureRecognizer else {
                configuredNavigationController = nil
                previousDelegate = nil
                ownsGestureDelegate = false
                return
            }

            if gesture.delegate === self {
                gesture.delegate = previousDelegate
            }
            configuredNavigationController = nil
            previousDelegate = nil
            ownsGestureDelegate = false
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let navigationController =
                    configuredNavigationController else {
                return false
            }
            return navigationController.viewControllers.count > 1
                && navigationController.transitionCoordinator == nil
        }
    }
}

extension View {
    /// 保留自定义导航栏视觉，同时恢复系统交互式返回动画与取消手势。
    func interactivePopGestureEnabled(
        _ isEnabled: Bool = true
    ) -> some View {
        background {
            InteractivePopGestureConfigurator(isEnabled: isEnabled)
                .frame(width: 0, height: 0)
        }
    }
}

// MARK: - Secondary Navigation

/// 二级页面统一返回按钮：保持钱包与充值页的圆形弱底样式。
struct CompactSecondaryBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(DB.panel.opacity(0.78))
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(DB.divider, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("common.back".localized)
    }
}

/// 二级页面统一紧凑导航栏。
struct CompactProfileNavigationHeader: View {
    @Environment(\.dismiss) private var dismiss

    let title: String

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            HStack {
                CompactSecondaryBackButton {
                    dismiss()
                }

                Spacer()
            }
        }
        .frame(height: 46)
    }
}

extension View {
    /// 为使用系统导航栏的二级页替换统一导航栏，并保留原生侧滑返回。
    func compactSecondaryNavigation(title: String) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                CompactProfileNavigationHeader(title: title)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .background(DB.black)
            }
            .interactivePopGestureEnabled()
    }
}

// MARK: - Rewards Visuals

enum RewardCoinMotion: Equatable {
    case none
    case bounce
    case spin
}

/// Rewards 页面统一使用的立体 R 金币素材。
struct RewardCoinBadge: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let size: CGFloat
    var tint: Color = .white
    var glowColor: Color = DT.coinGold
    var glowRadius: CGFloat = 0
    var brightness: Double = 0
    var motion: RewardCoinMotion = .none

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: accessibilityReduceMotion || motion == .none
            )
        ) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let bounceY = motion == .bounce && !accessibilityReduceMotion
                ? sin(seconds * .pi * 2 / 1.15) * 2.5
                : 0
            let spinDegrees = motion == .spin && !accessibilityReduceMotion
                ? seconds.truncatingRemainder(dividingBy: 3.2) / 3.2 * 360
                : 0

            ZStack {
                Image("RewardCoinIcon")
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(tint)
                    .brightness(brightness)
                    .shadow(
                        color: glowRadius > 0
                            ? glowColor.opacity(0.44)
                            : .clear,
                        radius: glowRadius
                    )
                    .offset(y: bounceY)
                    .rotation3DEffect(
                        .degrees(spinDegrees),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

/// “今日可赚”入口使用的暗酒红金币奖励胶囊，整体轻微跳动。
struct RewardEarnableBadge: View {
    @Environment(\.accessibilityReduceMotion)
    private var accessibilityReduceMotion

    let value: Int

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: accessibilityReduceMotion
            )
        ) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let bounceY = accessibilityReduceMotion
                ? 0
                : sin(seconds * .pi * 2 / 1.5) * 2.5

            HStack(spacing: 5) {
                RewardCoinBadge(
                    size: 20,
                    glowColor: DT.coinGold,
                    glowRadius: 0
                )

                Text("+\(value)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DT.rewardBadgeText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.leading, 5)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DT.rewardBadgeBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DT.rewardBadgeBorder.opacity(0.65), lineWidth: 0.75)
            }
            .offset(y: bounceY)
        }
        .frame(height: 34)
        .accessibilityLabel("reward.earnable_accessibility".localizedFormat(value))
    }
}

/// 三枚金币叠放图标，用于购买金币等入口。
struct RewardCoinStackIcon: View {
    let size: CGFloat
    var tint: Color = .white
    var glowColor: Color = DT.coinGold

    var body: some View {
        ZStack {
            RewardCoinBadge(
                size: size * 0.7,
                tint: tint,
                glowColor: glowColor
            )
            .offset(x: -size * 0.25, y: size * 0.14)

            RewardCoinBadge(
                size: size * 0.7,
                tint: tint,
                glowColor: glowColor
            )
            .offset(x: size * 0.25, y: size * 0.14)

            RewardCoinBadge(
                size: size * 0.78,
                tint: tint,
                glowColor: glowColor,
                glowRadius: 1
            )
            .offset(y: -size * 0.12)
        }
        .frame(width: size * 1.3, height: size)
        .accessibilityHidden(true)
    }
}

/// Rewards 首屏右侧的金色播放圆环与黑红舞台氛围素材。
struct RewardsHeroArtwork: View {
    let width: CGFloat
    let height: CGFloat
    var opacity: Double = 1
    var alignment: Alignment = .trailing

    var body: some View {
        Image("RewardsHeroArtwork")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height, alignment: alignment)
            .clipped()
            .blendMode(.screen)
            .opacity(opacity)
            .accessibilityHidden(true)
    }
}

// MARK: - VIP Crown

/// 可复用的会员皇冠素材。
///
/// 黑色背景通过 `.screen` 混合模式自然融入深色界面；可按使用场景调整尺寸、颜色与光晕。
struct VIPCrownView: View {
    let width: CGFloat
    var height: CGFloat? = nil
    var tint: Color = .white
    var opacity: Double = 1
    var glowColor: Color? = nil
    var glowRadius: CGFloat = 0

    var body: some View {
        ZStack {
            if glowRadius > 0 {
                crownImage(color: glowColor ?? tint)
                    .blur(radius: glowRadius)
                    .opacity(0.55)
                    .blendMode(.screen)
            }

            crownImage(color: tint)
                .blendMode(.screen)
        }
        .frame(width: width, height: height)
        .opacity(opacity)
        .accessibilityHidden(true)
    }

    private func crownImage(color: Color) -> some View {
        Image("ProfileVIPCrown")
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .colorMultiply(color)
    }
}

// MARK: - Cover Image View
/// 封面图片异步加载组件，使用项目共享 ImageLoader 内存缓存
///
/// 加载中/失败均显示暗黑骨架占位，避免慢网或坏图时出现突兀色块。
///
/// 使用示例：
/// ```swift
/// CoverImageView(url: drama.coverURL)           // 2:3 竖版海报
/// CoverImageView(url: banner.imageName, aspectRatio: 16/9, cornerRadius: DT.Radius.lg)
/// ```
struct CoverImageView: View {
    let url: String
    var aspectRatio: CGFloat = DT.Layout.cardAspectRatio // 默认 2:3 竖版
    var cornerRadius: CGFloat = DB.posterRadius
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    @StateObject private var imageLoader = ImageLoader()

    var body: some View {
        ZStack {
            placeholderGradient

            if imageLoader.imageKey == ImageLoader.canonicalURLString(url), let image = imageLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            }
        }
        .applySize(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) {
            await imageLoader.load(url)
        }
    }
    
    /// 渐变占位背景
    private var placeholderGradient: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [DT.Color.bgCoverPlaceholderAltStart, DT.Color.bgCoverPlaceholderAltEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(aspectRatio, contentMode: .fit)
    }
}

// MARK: - Size Application Helper
private extension View {
    @ViewBuilder
    func applySize(width: CGFloat?, height: CGFloat?) -> some View {
        if let w = width, let h = height {
            self.frame(width: w, height: h)
        } else if let w = width {
            self.frame(width: w)
        } else if let h = height {
            self.frame(height: h)
        } else {
            self
        }
    }
}

// MARK: - Cover Image View for Banner
/// Banner 专用封面组件 — 16:9 比例，大圆角
struct BannerCoverImage: View {
    let url: String
    
    var body: some View {
        CoverImageView(
            url: url,
            aspectRatio: DT.Layout.bannerAspectRatio,
            cornerRadius: DT.Radius.lg
        )
    }
}

// MARK: - Continue Watching Section
struct ContinueWatchingSection: View {
    let dramas: [DramaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Space.sm) {
            HStack {
                Text(L10n.youAreWatching)
                    .font(DT.Font.subtitle)
                    .foregroundColor(DT.Color.textPrimary)

                Spacer()

                Button(L10n.viewAll) {}
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)
            }
            .padding(.horizontal, DT.Space.pageH)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Space.md) {
                    ForEach(dramas) { drama in
                        VStack(alignment: .leading, spacing: DT.Space.xs) {
                            ZStack(alignment: .bottom) {
                                CoverImageView(
                                    url: drama.coverURL,
                                    aspectRatio: DT.Layout.cardAspectRatio,
                                    cornerRadius: DB.posterRadius,
                                    width: 100,
                                    height: 140
                                )

                                if let progress = drama.progressPercentage {
                                    GeometryReader { geo in
                                        Rectangle()
                                            .fill(DT.logoRed)
                                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                                    }
                                    .frame(height: 3)
                                }
                            }

                            Text(drama.title)
                                .font(DT.Font.caption)
                                .fontWeight(.medium)
                                .foregroundColor(DT.Color.textPrimary)
                                .frame(width: 100)
                                .lineLimit(1)

                            Text("\(drama.currentEpisode)/\(drama.episodeCount)\(L10n.shortEpisodeCount)")
                                .font(DT.Font.small)
                                .foregroundColor(DT.Color.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, DT.Space.pageH)
            }
        }
    }
}

// MARK: - Section Header
struct SectionHeaderView: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: DT.Space.sm) {
            // Decorative left bar
            Rectangle()
                .fill(DT.logoRed)
                .frame(width: 3, height: 16)
                .cornerRadius(1.5)

            Text(title)
                .font(DT.Font.sectionTitle)
                .foregroundColor(DT.Color.textPrimary)

            Spacer()

            Button(action: action) {
                HStack(spacing: 2) {
                    Text(L10n.more)
                        .font(DT.Font.caption)
                    Image(systemName: "chevron.right")
                        .font(DT.Font.small)
                }
                .foregroundColor(DT.Color.textSecondary)
            }
        }
    }
}

// MARK: - Ranking List View
struct RankingListView: View {
    let dramas: [DramaItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(dramas.enumerated()), id: \.element.id) { index, drama in
                RankingRow(index: index + 1, drama: drama)
            }
        }
    }
}

// MARK: - Ranking Row
struct RankingRow: View {
    let index: Int
    let drama: DramaItem

    private var rankColor: SwiftUI.Color {
        index <= 3 ? DT.brandGold : DT.Color.textSecondary
    }

    private var rankWeight: SwiftUI.Font.Weight {
        index <= 3 ? .heavy : .bold
    }

    var body: some View {
        HStack(spacing: DT.Space.md) {
            // Rank number
            Text("\(index)")
                .font(DT.Font.body(20, weight: rankWeight))
                .foregroundColor(rankColor)
                .frame(width: 32)

            // Cover
            CoverImageView(
                url: drama.coverURL,
                aspectRatio: DT.Layout.cardAspectRatio,
                cornerRadius: DB.posterRadius,
                width: 60,
                height: 80
            )

            // Info
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(drama.title)
                    .font(DT.Font.body(14))
                    .fontWeight(.semibold)
                    .foregroundColor(DT.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: DT.Space.xs) {
                    ForEach(drama.tags, id: \.self) { tag in
                        Text(tag)
                            .font(DT.Font.small)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DT.Color.bgCard)
                            .cornerRadius(3)
                            .foregroundColor(DT.Color.textSecondary)
                    }
                }

                HStack(spacing: DT.Space.sm) {
                    HStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(DT.Font.small)
                        Text(drama.formattedViewCount)
                            .font(DT.Font.small)
                    }
                    .foregroundColor(DT.Color.textSecondary)

                    Text("\(L10n.totalEpisodesPrefix)\(drama.episodeCount)\(L10n.shortEpisodeCount)")
                        .font(DT.Font.small)
                        .foregroundColor(DT.Color.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(DT.Font.tabLabel)
                .foregroundColor(DT.Color.textTertiary)
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, DT.Space.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Badge Tag View (Task20: shared badge rendering)

/// Renders a single badge tag for player / recommend card overlays.
/// Uses feed-style styling with configurable foreground/background colors.
struct DramaBadgeTagView: View {
    let tag: L10n.BadgeTag
    let drama: DramaItem

    var body: some View {
        switch tag {
        case .vip:
            feedTag(L10n.badgeTagLabel(.vip), bg: .goldVipBadgeBg, fg: .goldVipBadgeFg)
        case .hot:
            feedTag(L10n.badgeTagLabel(.hot), bg: .white.opacity(0.12), fg: .white.opacity(0.85))
        case .trending:
            feedTag(L10n.badgeTagLabel(.trending), bg: .white.opacity(0.12), fg: .white.opacity(0.85))
        case .new:
            feedTag(L10n.badgeTagLabel(.new), bg: .white.opacity(0.12), fg: .white.opacity(0.85))
        case .category:
            let cat = L10n.categoryDisplayName(drama.category)
            if !cat.isEmpty {
                feedTag(cat, bg: .white.opacity(0.12), fg: .white.opacity(0.85))
            }
        }
    }

    private func feedTag(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// 会员权益统一使用的 HD 徽章；尺寸和颜色可由不同页面按需调整。
struct HDBadgeIconView: View {
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let lineWidth: CGFloat
    let textSize: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(color, lineWidth: lineWidth)
                .frame(width: width, height: height)

            Text("HD")
                .font(.system(
                    size: textSize,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundColor(color)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Shared Episode Unlock Overlay

/// 全 App 共用的剧集解锁弹窗。
///
/// 播放器只负责权益状态、购买和解锁回调；VIP/金币选择、挽留层和锁定态的视觉实现全部在这里维护。
struct EpisodeUnlockOverlay: View {
    let state: EpisodeUnlockFlowState
    let containerWidth: CGFloat
    let containerHeight: CGFloat
    let safeAreaTop: CGFloat
    let safeAreaBottom: CGFloat
    let onClose: () -> Void
    let onOpenPrimary: () -> Void
    let onSelectMethod: (EpisodeUnlockFlowState.Selection) -> Void
    let onPrimaryAction: () -> Void
    let onRewardedAd: () -> Void
    let onExitPlayback: () -> Void

    private enum PanelLayout {
        static func primaryHeight(containerHeight: CGFloat) -> CGFloat {
            min(430, max(320, containerHeight * 0.46))
        }

        static func bottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
            max(34, safeAreaBottom + 18)
        }
    }

    private var unlockGold: Color { Color(red: 1.0, green: 0.76, blue: 0.20) }
    private var unlockPaleGold: Color { Color(red: 1.0, green: 0.90, blue: 0.62) }

    private var unlockSheetGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.13, green: 0.11, blue: 0.08), Color(red: 0.055, green: 0.05, blue: 0.044), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        let standardRetentionHeight: CGFloat = 206
        let upwardAdjustment: CGFloat = 32
        let retentionBottomInset = max(safeAreaBottom + 44, containerHeight * 0.1)
        let retentionTopInset = max(
            safeAreaTop + 24,
            containerHeight - retentionBottomInset - standardRetentionHeight - upwardAdjustment
        )

        ZStack {
            Color.black.opacity(0.76)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            switch state.presentation {
            case .primary:
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    primaryPanel
                        .frame(width: containerWidth)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            case .retention:
                retentionDialog
                    .frame(width: min(containerWidth - 40, 420))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, retentionTopInset)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            case .lockedFrame:
                finalLockedFrame
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(true)
    }

    private var primaryPanel: some View {
        let panelHeight = PanelLayout.primaryHeight(containerHeight: containerHeight)
        let isCompact = panelHeight < 370
        let choiceHeight: CGFloat = isCompact ? 62 : 76

        return VStack(spacing: 0) {
            HStack {
                if !state.vipOnly {
                    unlockMetadata
                } else {
                    Label("player.vip_exclusive".localized, systemImage: "crown.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(unlockPaleGold)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .disabled(state.isProcessing)
                .accessibilityLabel("general.close".localized)
            }

            VStack(spacing: isCompact ? 8 : 10) {
                unlockChoice(
                    title: "player.vip_all_access".localized,
                    subtitle: "player.vip_all_access_detail".localized,
                    icon: "crown.fill",
                    selected: state.selection == .vip,
                    height: choiceHeight
                ) { onSelectMethod(.vip) }

                if state.canUnlockWithCoins {
                    unlockChoice(
                        title: "player.coin_unlock".localized,
                        subtitle: "player.coin_unlock_detail".localized,
                        icon: "bitcoinsign.circle.fill",
                        selected: state.selection == .coins,
                        height: choiceHeight
                    ) { onSelectMethod(.coins) }
                }
            }
            .padding(.top, isCompact ? 10 : 18)

            Spacer(minLength: isCompact ? 8 : 14)

            if let message = state.errorMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.38))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    if state.isProcessing && !state.isPreparingRewardedAd {
                        ProgressView().tint(.black)
                    }
                    Text(state.primaryButtonTitle)
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: isCompact ? 52 : 58)
                .background(
                    LinearGradient(
                        colors: [.white, unlockPaleGold, unlockGold],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .shadow(color: unlockGold.opacity(0.25), radius: 18, y: 8)
            }
            .disabled(state.isProcessing)

            Group {
                if state.canUnlockWithAd {
                    Button(action: onRewardedAd) {
                        HStack(spacing: 7) {
                            if state.isPreparingRewardedAd {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white.opacity(0.72))
                            }
                            Text("player.ad_unlock".localized)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.62))
                                .underline(color: .white.opacity(0.28))
                        }
                    }
                    .disabled(state.isProcessing)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(height: 18)
            .padding(.top, isCompact ? 8 : 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, isCompact ? 14 : 22)
        .padding(.bottom, PanelLayout.bottomPadding(safeAreaBottom: safeAreaBottom))
        .frame(height: panelHeight, alignment: .top)
        .background(
            unlockSheetGradient,
            in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .stroke(
                    LinearGradient(colors: [unlockGold.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .environment(\.colorScheme, .dark)
    }

    private var unlockMetadata: some View {
        HStack(spacing: 13) {
            unlockMetadataItem(label: "player.this_episode".localized, value: state.coinCost)
            Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 18)
            unlockMetadataItem(label: "player.balance".localized, value: state.balance)
        }
    }

    private func unlockMetadataItem(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Image(systemName: "bitcoinsign.circle.fill")
                .foregroundStyle(unlockGold)
            Text("\(value)")
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white.opacity(0.86))
    }

    private func unlockChoice(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        height: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? unlockGold : .white.opacity(0.55))
                    .frame(width: 36, height: 36)
                    .background(selected ? unlockGold.opacity(0.12) : .white.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(selected ? unlockGold.opacity(0.12) : .white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(selected ? unlockGold : .white.opacity(0.08), lineWidth: selected ? 1.6 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15))
        }
        .disabled(state.isProcessing)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var retentionDialog: some View {
        VStack(spacing: 12) {
            HStack {
                Text(state.vipOnly ? "player.continue_watching".localized : "player.choose_unlock_method".localized)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(unlockPaleGold)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .disabled(state.isProcessing)
                .accessibilityLabel("general.close".localized)
            }

            retentionActionButton(
                title: state.vipOnly ? "player.join_vip_continue".localized : "player.continue_unlock".localized,
                icon: state.vipOnly ? "crown.fill" : "lock.fill",
                selected: true,
                disabled: state.isProcessing,
                action: onOpenPrimary
            )

            if state.canUnlockWithAd {
                retentionActionButton(
                    title: "player.ad_unlock".localized,
                    icon: "play.rectangle.fill",
                    selected: false,
                    disabled: state.isProcessing,
                    action: onRewardedAd
                )
            }

            if state.isProcessing {
                ProgressView().tint(unlockGold)
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.38))
            }
        }
        .padding(18)
        .background(
            unlockSheetGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(colors: [unlockGold.opacity(0.5), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
    }

    private func retentionActionButton(
        title: String,
        icon: String,
        selected: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(selected ? .black : unlockPaleGold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [.white, unlockPaleGold, unlockGold], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(unlockGold.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(unlockGold.opacity(selected ? 0 : 0.72), lineWidth: selected ? 0 : 1.4)
                )
        }
        .disabled(disabled)
        .opacity(disabled ? 0.58 : 1)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var finalLockedFrame: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(unlockGold)
            Text("player.episode_not_unlocked".localized)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Button(action: onOpenPrimary) {
                Text("player.unlock_now".localized)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .frame(height: 44)
                    .background(unlockPaleGold, in: Capsule())
            }
            Button(action: onExitPlayback) {
                Text("player.exit_playback".localized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(unlockPaleGold)
                    .padding(.horizontal, 28)
                    .frame(height: 44)
                    .overlay(Capsule().stroke(unlockGold.opacity(0.62), lineWidth: 1))
            }
        }
    }
}

private struct EpisodePlayingWaveform: View {
    @State private var isAnimating = false

    private let activeScales: [CGFloat] = [0.55, 0.82, 1.0, 0.68, 0.9]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(activeScales.indices, id: \.self) { index in
                Capsule()
                    .fill(.white)
                    .frame(width: 2, height: 12)
                    .scaleEffect(y: isAnimating ? activeScales[index] : 0.38, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.42)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.06),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 18, height: 12)
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
        .accessibilityHidden(true)
    }
}

struct EpisodeUnlockVerificationOverlay: View {
    var body: some View {
        // 只负责拦截重复操作，不再额外绘制 spinner；播放器自己的首帧 loading 是唯一反馈。
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
        .allowsHitTesting(true)
        .accessibilityLabel("player.unlock_pending".localized)
    }
}

// MARK: - Shared Episode Picker Sheet

/// 推荐页、Series 播放页和全屏播放器共用的选集弹层。
///
/// 这里只维护一套视觉和交互实现；各入口只负责提供剧集数据、当前集和选集后的业务回调。
struct EpisodePickerSheet: View {
    let drama: DramaItem
    let episodes: [Episode]
    let currentEpisode: Int
    let unlockedEpisodes: Set<Int>
    let episodesLoaded: Bool
    let episodesLoadError: String?
    @Binding var isPresented: Bool
    var onSelectEpisode: (Int) -> Void
    var onRetryEpisodes: (() -> Void)?

    private enum Detent {
        case compact
        case expanded
    }

    private struct EpisodeVisualState {
        let wasLocked: Bool
        let isUnlocked: Bool
        let requiresVIP: Bool

        var isLockedForDisplay: Bool { wasLocked && !isUnlocked }
        var showsLockBadge: Bool { !requiresVIP && isLockedForDisplay }
        var showsUnlockedBadge: Bool { !requiresVIP && wasLocked && isUnlocked }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
    private let rangeSize = 30
    @State private var selectedRange = 0
    @State private var detent: Detent = .compact
    @State private var isSynopsisExpanded = false
    @GestureState private var dragTranslation: CGFloat = 0

    private var totalEpisodes: Int {
        episodes.map(\.episodeNumber).max() ?? 0
    }

    private var metadataEpisodeCount: Int {
        episodesLoaded ? totalEpisodes : drama.episodeCount
    }

    private var ranges: [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var start = 1
        while start <= totalEpisodes {
            let end = min(start + rangeSize - 1, totalEpisodes)
            result.append(start...end)
            start += rangeSize
        }
        return result
    }

    private var selectedEpisodeRange: ClosedRange<Int> {
        guard let first = ranges.first else { return 1...1 }
        guard ranges.indices.contains(selectedRange) else { return first }
        return ranges[selectedRange]
    }

    private var selectedEpisodeNumbers: [Int] {
        guard !episodes.isEmpty else { return [] }
        return episodes
            .filter { selectedEpisodeRange.contains($0.episodeNumber) }
            .map(\.episodeNumber)
            .sorted()
    }

    var body: some View {
        GeometryReader { geo in
            let compactHeight = min(geo.size.height - 24, max(420, geo.size.height * 0.60))
            let expandedHeight = min(
                geo.size.height - geo.safeAreaInsets.top - 12,
                max(compactHeight, geo.size.height * 0.80)
            )
            let baseHeight = detent == .compact ? compactHeight : expandedHeight
            let visibleHeight = min(
                expandedHeight,
                max(compactHeight, baseHeight - dragTranslation)
            )

            ZStack(alignment: .bottom) {
                Color.black.opacity(0.52)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                VStack(spacing: 0) {
                    sheetChrome

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            header(containerWidth: geo.size.width)
                            synopsisBlock

                            Rectangle()
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 1)
                                .padding(.horizontal, 20)

                            episodeSection
                        }
                        .padding(.bottom, max(20, geo.safeAreaInsets.bottom + 12))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .frame(maxWidth: .infinity)
                .frame(height: visibleHeight, alignment: .top)
                .frame(width: geo.size.width)
                .background(DB.panelElevated)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 22,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 22,
                        style: .continuous
                    )
                )
                .ignoresSafeArea(edges: .bottom)
                .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: detent)
            }
            .ignoresSafeArea(edges: .bottom)
            .onAppear(perform: alignSelectedRange)
            .onChange(of: drama.id) { _, _ in alignSelectedRange() }
            .onChange(of: episodes.count) { _, _ in alignSelectedRange() }
            .onChange(of: episodesLoaded) { _, _ in alignSelectedRange() }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var sheetChrome: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 48, height: 5)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 50)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .gesture(sheetDragGesture)
    }

    private func header(containerWidth: CGFloat) -> some View {
        let posterWidth = min(150, max(106, containerWidth * 0.385))
        let posterHeight = posterWidth * 1.53

        return HStack(alignment: .top, spacing: 16) {
            CoverImageView(
                url: drama.coverURL,
                aspectRatio: 2.0 / 3.0,
                cornerRadius: DB.posterRadius,
                width: posterWidth,
                height: posterHeight
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(drama.title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Text(metadataText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.52))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if drama.rating > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(DB.logoRed)
                            Text(String(format: "%.1f", drama.rating))
                        }
                    }

                    if drama.rating > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 1, height: 14)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "play")
                            .font(.system(size: 12, weight: .semibold))
                        Text(L10n.viewsCount(drama.formattedViewCount))
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.58))

                HStack(spacing: 6) {
                    Text("\(L10n.playerNowPlaying) \(L10n.playerEpisodeNumber(max(1, currentEpisode)))")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(DB.logoRed)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(DB.logoRed.opacity(0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(DB.logoRed.opacity(0.24), lineWidth: 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
    }

    private var synopsisBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.synopsis)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                if !drama.synopsis.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isSynopsisExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSynopsisExpanded ? L10n.collapse : L10n.expand)
                            Image(systemName: isSynopsisExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(drama.synopsis.isEmpty ? "home.synopsis_unavailable".localized : drama.synopsis)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.78))
                .lineSpacing(4)
                .lineLimit(isSynopsisExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .leading) {
                Text(L10n.tabEpisodes)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                if episodesLoaded, !episodes.isEmpty, ranges.count > 1 {
                    rangeTabs
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .frame(maxWidth: .infinity)

            if !episodesLoaded {
                ProgressView()
                    .tint(.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if let episodesLoadError {
                VStack(spacing: 10) {
                    Text(episodesLoadError)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)

                    if let onRetryEpisodes {
                        Button(L10n.retry, action: onRetryEpisodes)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DB.logoRed)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if episodes.isEmpty {
                Text(L10n.noContent)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(selectedEpisodeNumbers, id: \.self) { episode in
                        episodeCell(episode)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    private var rangeTabs: some View {
        HStack(spacing: 16) {
            ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedRange = index
                    }
                } label: {
                    VStack(spacing: 6) {
                        Text("\(range.lowerBound)–\(range.upperBound)")
                            .font(.system(size: 14, weight: selectedRange == index ? .bold : .medium))
                            .foregroundColor(selectedRange == index ? DB.logoRed : .white.opacity(0.55))

                        Capsule()
                            .fill(selectedRange == index ? DB.logoRed : Color.clear)
                            .frame(width: 32, height: 3)
                    }
                    .frame(minWidth: 58)
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func episodeCell(_ episodeNumber: Int) -> some View {
        let state = visualState(for: episodeNumber)
        let isCurrent = episodeNumber == currentEpisode
        let isLocked = state.isLockedForDisplay

        return Button {
            // 锁图标只是状态预览；真正的播放/权益判断仍由调用方负责。
            onSelectEpisode(episodeNumber)
            dismiss()
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isCurrent
                            ? DB.logoRed
                            : (isLocked ? Color.white.opacity(0.055) : Color.white.opacity(0.085))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                state.requiresVIP && !isCurrent
                                    ? DB.gold.opacity(0.30)
                                    : Color.white.opacity(isCurrent ? 0 : 0.07),
                                lineWidth: 1
                            )
                    }

                Text("\(episodeNumber)")
                    .font(.system(size: 18, weight: isCurrent ? .bold : .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                if isCurrent {
                    EpisodePlayingWaveform()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 6)
                }

                if state.requiresVIP {
                    Text("VIP")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DB.gold)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(DB.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(DB.gold.opacity(0.35), lineWidth: 1)
                        }
                        .padding(.top, 7)
                        .padding(.trailing, 7)
                } else if state.showsLockBadge {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                } else if state.showsUnlockedBadge {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func visualState(for episodeNumber: Int) -> EpisodeVisualState {
        let episode = episodes.first(where: { $0.episodeNumber == episodeNumber })
        let wasLocked = episode?.isLocked ?? true
        let isUnlocked = !wasLocked
            || episode?.isUnlocked == true
            || unlockedEpisodes.contains(episodeNumber)
        let requiresVIP = episode?.requiresVIP ?? false

        return EpisodeVisualState(
            wasLocked: wasLocked,
            isUnlocked: isUnlocked,
            requiresVIP: requiresVIP
        )
    }

    private var metadataText: String {
        var parts: [String] = []
        let category = L10n.categoryDisplayName(drama.category)
        if !category.isEmpty { parts.append(category) }
        if let tag = drama.tags.first, !tag.isEmpty { parts.append(tag) }
        parts.append("\(metadataEpisodeCount)\(L10n.shortEpisodeCount)")
        return parts.joined(separator: " · ")
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let translation = value.translation.height
                let projected = value.predictedEndTranslation.height

                if translation < -56 || projected < -96 {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                        detent = .expanded
                    }
                } else if translation > 56 || projected > 96 {
                    if detent == .expanded {
                        withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                            detent = .compact
                        }
                    } else {
                        dismiss()
                    }
                }
            }
    }

    private func alignSelectedRange() {
        guard let index = ranges.firstIndex(where: { $0.contains(currentEpisode) }) else { return }
        selectedRange = index
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

private extension Color {
    static let goldVipBadgeBg = Color(red: 0.85, green: 0.72, blue: 0.38).opacity(0.25)
    static let goldVipBadgeFg = Color(red: 0.85, green: 0.72, blue: 0.38)
}
