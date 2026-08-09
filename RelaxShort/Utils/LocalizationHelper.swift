import Foundation

// MARK: - L10n

/// 本地化便捷访问器
/// 所有 UI 字符串通过此枚举统一访问，支持应用内实时切换。
///
/// 用法：
/// ```swift
/// Text(L10n.featured)
/// Text(L10n.checkedInDays(7))
/// ```
///
/// 查找由 `AppLocalization` 统一完成，目标语言缺键时回退英文。
enum L10n {

    // MARK: - Core Lookup

    private static func loc(_ key: String, formatArgs: [CVarArg] = []) -> String {
        AppLocalization.text(key, arguments: formatArgs)
    }

    // MARK: - General

    static var cancel: String { loc("general.cancel") }
    static var confirm: String { loc("general.confirm") }
    static var more: String { loc("general.more") }
    static var share: String { loc("general.share") }
    static var comment: String { loc("general.comment") }
    static var download: String { loc("general.download") }
    static var retry: String { loc("general.retry") }
    static var loading: String { loc("general.loading") }
    static var noContent: String { loc("general.no_content") }
    static var generalError: String { loc("general.error") }
    static var generalOk: String { loc("general.ok") }

    // MARK: - Search

    static var hotSearchTab: String { loc("search.hot_search_tab") }
    static var hotPlayTab: String { loc("search.hot_play_tab") }
    static var newDramaTab: String { loc("search.new_drama_tab") }
    static var noHotSearch: String { loc("search.no_hot_search") }
    static var noHotPlay: String { loc("search.no_hot_play") }
    static var noNewDrama: String { loc("search.no_new_drama") }
    static var searchPlaceholder: String { loc("search.placeholder") }
    static var noSearchResults: String { loc("search.no_results") }
    static var tryDifferentKeyword: String { loc("search.try_different_keyword") }
    static var searchFailed: String { loc("search.failed") }
    static var recentSearches: String { loc("search.recent_searches") }
    static var trendingSearches: String { loc("search.trending_searches") }
    static var clearSearchHistory: String { loc("search.clear_history") }
    static var clearSearchText: String { loc("search.clear_text") }
    static var topSearchedTab: String { loc("search.tab.top_searched") }
    static var mostTrendingTab: String { loc("search.tab.most_trending") }
    static var newReleasesTab: String { loc("search.tab.new_releases") }
    static func searchRankAccessibility(rank: Int, title: String) -> String {
        loc(
            "search.rank_accessibility_format",
            formatArgs: [rank, title]
        )
    }
    static var searchHint: String { loc("search.hint") }

    // MARK: - Home

    static var featured: String { loc("home.featured") }
    static var rankings: String { loc("home.rankings") }
    static var youAreWatching: String { loc("home.you_are_watching") }
    static var viewAll: String { loc("home.view_all") }
    static var shortEpisodeCount: String { loc("home.episode_count") }
    static var noAnime: String { loc("home.no_anime") }
    static var homeSearchPlaceholder: String { loc("home.search_placeholder") }

    // MARK: - Rank

    static var rankSearchPlaceholder: String { loc("rank.search_placeholder") }
    static var noRankData: String { loc("rank.no_data") }

    // MARK: - Coin Reward

    static var coinRewardTab: String { loc("coin.tab") }
    static var memberPointsTab: String { loc("coin.member_points_tab") }
    static var myCoins: String { loc("coin.my_coins") }
    static var rules: String { loc("coin.rules") }
    static var rewardRules: String { loc("coin.reward_rules") }
    static func checkedInDays(_ days: Int) -> String {
        loc("coin.checked_in_days", formatArgs: [days])
    }
    static var watchAdForCoins: String { loc("coin.watch_ad_for_coins") }
    static var earnCoins: String { loc("coin.earn_coins") }
    static var appleDisclaimer: String { loc("coin.apple_disclaimer") }
    static var coinDailyCheckIn: String { loc("coin.daily_check_in") }

    // MARK: - Ad

    static func adWatchAdForCoins(_ coins: Int) -> String {
        loc("ad.watch_ad_for_coins", formatArgs: [coins])
    }
    static func adRemainingCount(_ count: Int) -> String {
        loc("ad.remaining_count", formatArgs: [count])
    }
    static var adLimitReached: String { loc("ad.limit_reached") }
    static var adWatchNow: String { loc("ad.watch_now") }
    static var adWatchedToday: String { loc("ad.watched_today") }
    static var adSkip: String { loc("ad.skip") }
    static var adLabel: String { loc("ad.label") }
    static func adSecondsRemaining(_ seconds: Int) -> String {
        loc("ad.seconds_remaining", formatArgs: [seconds])
    }
    static var adPleaseKeepWatching: String { loc("ad.please_keep_watching") }
    static var adWatchAdToUnlock: String { loc("ad.watch_ad_to_unlock") }
    static var adRewardTip: String { loc("ad.reward_tip") }
    static var adUnlockTip: String { loc("ad.unlock_tip") }
    static var adLoadFailed: String { loc("ad.load_failed") }
    static var adSponsoredLabel: String { loc("ad.sponsored_label") }
    static var adSponsoredContent1: String { loc("ad.sponsored_content_1") }
    static var adSponsoredContent2: String { loc("ad.sponsored_content_2") }
    static var adSponsoredContent3: String { loc("ad.sponsored_content_3") }
    static var adSponsoredContent4: String { loc("ad.sponsored_content_4") }
    static var adSponsoredSubtitle1: String { loc("ad.sponsored_subtitle_1") }
    static var adSponsoredSubtitle2: String { loc("ad.sponsored_subtitle_2") }
    static var adSponsoredSubtitle3: String { loc("ad.sponsored_subtitle_3") }
    static var adSponsoredSubtitle4: String { loc("ad.sponsored_subtitle_4") }
    static var adNativeDetailTitle: String { loc("ad.native_detail_title") }
    static var adNativeDetailBody: String { loc("ad.native_detail_body") }
    static var adLearnMore: String { loc("ad.learn_more") }
    static var adAppOpenTitle: String { loc("ad.app_open_title") }
    static var adAppOpenSubtitle: String { loc("ad.app_open_subtitle") }

    // MARK: - Membership

    static var joinMembership: String { loc("membership.join") }
    static var weeklyMember: String { loc("membership.weekly") }
    static var monthlyMember: String { loc("membership.monthly") }
    static var yearlyMember: String { loc("membership.yearly") }
    static var discount: String { loc("membership.discount") }
    static var joinNow: String { loc("membership.join_now") }
    static var rechargeInfo: String { loc("membership.recharge_info") }
    static var serviceAgreement: String { loc("membership.service_agreement") }
    static var weeklyDetail: String { loc("membership.weekly_detail") }
    static var monthlyDetail: String { loc("membership.monthly_detail") }
    static var yearlyDetail: String { loc("membership.yearly_detail") }
    static var membershipLoadFailed: String { loc("membership.load_failed") }
    static var terms1: String { loc("membership.terms_1") }
    static var terms2: String { loc("membership.terms_2") }
    static var terms3: String { loc("membership.terms_3") }

    // MARK: - Benefits

    static var benefitAllShows: String { loc("benefit.all_shows") }
    static var benefitDownload: String { loc("benefit.download") }
    static var benefitVipShows: String { loc("benefit.vip_shows") }
    static var benefitThemes: String { loc("benefit.themes") }
    static var benefitQuality: String { loc("benefit.quality") }
    static var benefitGift: String { loc("benefit.gift") }
    static var benefitFriendGift: String { loc("benefit.friend_gift") }
    static var benefitNoAds: String { loc("benefit.no_ads") }

    // MARK: - VIP

    static var unlockAllContent: String { loc("vip.unlock_all") }
    static func vipExpiry(_ date: String) -> String {
        loc("vip.vip_expiry", formatArgs: [date])
    }
    static func remainingDays(_ days: Int) -> String {
        loc("vip.remaining_days", formatArgs: [days])
    }
    static var recommended: String { loc("vip.recommended") }
    static var subscribeNow: String { loc("vip.subscribe_now") }
    static var renewMembership: String { loc("vip.renew") }
    static var autoRenewNotice: String { loc("vip.auto_renew_notice") }
    static var whyJoinVip: String { loc("vip.why_join") }
    static var vipTitle: String { loc("vip.title") }
    static var vipCenter: String { loc("vip.center") }

    // MARK: - Profile

    static var rechargeNow: String { loc("profile.recharge_now") }
    static var myWallet: String { loc("profile.my_wallet") }
    static var welfareCenter: String { loc("profile.welfare_center") }
    static var watchHistory: String { loc("profile.watch_history") }
    static var language: String { loc("profile.language") }
    static var customerService: String { loc("profile.customer_service") }
    static var simplifiedChinese: String { loc("profile.simplified_chinese") }
    static var featureInDevelopment: String { loc("profile.feature_in_development") }
    static var drama: String { loc("profile.drama") }
    static var dailyPoints: String { loc("profile.daily_points") }
    static var points: String { loc("profile.points") }
    static var quality: String { loc("profile.quality") }
    static func favoriteCount(_ count: Int) -> String {
        loc("profile.favorite_count", formatArgs: [count])
    }
    static var profileLoginToView: String { loc("profile.login_to_view") }
    static var profileLoginToSync: String { loc("profile.login_to_sync") }
    static var logout: String { loc("profile.logout") }
    static var confirmLogout: String { loc("profile.confirm_logout") }
    static var logoutConfirmMessage: String { loc("profile.logout_confirm_message") }

    // MARK: - Favorites

    static var myFavorites: String { loc("favorites.my_favorites") }
    static var noWatchHistory: String { loc("favorites.no_watch_history") }
    static var noBookmarks: String { loc("favorites.no_bookmarks") }
    static var loginToViewFavorites: String { loc("favorites.login_to_view") }
    static var loginToSync: String { loc("favorites.login_to_sync") }
    static var loginNow: String { loc("favorites.login_now") }
    static var continueWatching: String { loc("favorites.continue_watching") }
    static var watchNow: String { loc("favorites.watch_now") }
    static func watchedPercent(_ pct: Int) -> String {
        loc("favorites.watched_percent", formatArgs: [pct])
    }
    static func episodeProgress(_ current: Int, _ total: Int) -> String {
        loc("favorites.episode_progress", formatArgs: [current, total])
    }
    static func totalEpisodes(_ count: Int) -> String {
        loc("favorites.total_episodes", formatArgs: [count])
    }
    static var saveYourList: String { loc("favorites.save_your_list") }
    static var loginRecommendation: String { loc("favorites.login_recommendation") }
    static var loginWithGoogle: String { loc("favorites.login_google") }
    static var loginWithApple: String { loc("favorites.login_apple") }
    static var loginAgreement: String { loc("favorites.login_agreement") }
    static var favoritesAddedToast: String { loc("favorites.added_toast") }
    static var favoritesRemovedToast: String { loc("favorites.removed_toast") }

    // MARK: - Recommend

    static var noRecommendations: String { loc("recommend.no_content") }
    static var recommendLoadFailed: String { loc("recommend.load_failed") }
    static var pullToRefresh: String { loc("recommend.pull_to_refresh") }
    static var watchFullSeries: String { loc("recommend.watch_full_series") }
    static func episodeNumber(_ num: Int) -> String {
        loc("recommend.episode_number", formatArgs: [num])
    }
    static var synopsis: String { loc("recommend.synopsis") }
    static var expand: String { loc("player.expand") }
    static func tagDisplayName(_ tag: String) -> String { loc("tag.\(tag)") }

    /// Returns a user-facing category name.
    /// Known backend names/codes (Romance, Fantasy, Thriller, Drama, Action, and their lowercase
    /// variants) map through the fallback dictionary. Unknown non-empty categories return the raw
    /// category text after stripping any accidental `category.` prefix. Empty string means
    /// "no category tag should be rendered".
    static func categoryDisplayName(_ category: String) -> String {
        guard !category.isEmpty else { return "" }
        let result = loc("category.\(category)")
        // If the result still looks like a localization key (e.g. "category.SciFi"),
        // strip the prefix and return the raw name.
        if result.hasPrefix("category.") {
            return String(result.dropFirst("category.".count))
        }
        return result
    }

    // MARK: - Badge Tags (Task20: semantic badge display)

    /// Describes a single badge tag for player / recommend card overlays.
    enum BadgeTag: String, CaseIterable {
        case vip, hot, trending, new, category
    }

    /// Ordered badge tag keys for `drama`, respecting compact display rules.
    /// - VIP / Members tag: shown when `isMemberOnly || isVIPOnly || badge == .vip`
    /// - Hot: shown when `isHot || badge == .hot`
    /// - Trending: shown when `isTrending`
    /// - New: shown when `badge == .new`
    /// - Category: shown when `category` is non-empty
    static func dramaBadgeTags(for drama: DramaItem) -> [BadgeTag] {
        var tags: [BadgeTag] = []
        if drama.isMemberOnly || drama.isVIPOnly || drama.badge == .vip {
            tags.append(.vip)
        }
        if drama.isHot || drama.badge == .hot {
            tags.append(.hot)
        }
        if drama.isTrending {
            tags.append(.trending)
        }
        if drama.badge == .new {
            tags.append(.new)
        }
        if !drama.category.isEmpty {
            tags.append(.category)
        }
        // Keep tag count compact — max 4
        if tags.count > 4 {
            tags = Array(tags.prefix(4))
        }
        return tags
    }

    /// Human-readable label for a `BadgeTag`.
    static func badgeTagLabel(_ tag: BadgeTag) -> String {
        switch tag {
        case .vip:       return loc("badge.vip")
        case .hot:       return loc("badge.hot")
        case .trending:  return loc("badge.trending")
        case .new:       return loc("badge.new")
        case .category:  return "" // filled by caller from categoryDisplayName
        }
    }

    // MARK: - Exit Guide

    static var newDramaBenefit: String { loc("exit.new_drama_benefit") }
    static var rewardBenefit: String { loc("exit.reward_benefit") }
    static var promoBenefit: String { loc("exit.promo_benefit") }
    static var enableNotificationsTitle: String { loc("exit.enable_title") }
    static var enableNotificationsBody: String { loc("exit.enable_body") }
    static var enableNotifications: String { loc("exit.enable_button") }
    static var notNow: String { loc("exit.skip_button") }

    // MARK: - Shared Components

    static var totalEpisodesPrefix: String { loc("shared.total_episodes_prefix") }

    // MARK: - Theme

    static var themeSystem: String { loc("theme.system") }
    static var themeLight: String { loc("theme.light") }
    static var themeDark: String { loc("theme.dark") }
    static var themeMenuTitle: String { loc("theme.menu.title") }
    static var themeSheetTitle: String { loc("theme.sheet.title") }

    // MARK: - Language Names

    static var langZhHans: String { loc("lang.zh_hans") }
    static var langZhHant: String { loc("lang.zh_hant") }
    static var langEn: String { loc("lang.en") }
    static var langKo: String { loc("lang.ko") }
    static var langJa: String { loc("lang.ja") }
    static var langPt: String { loc("lang.pt") }
    static var langEs: String { loc("lang.es") }
    static var langAr: String { loc("lang.ar") }

    // MARK: - Player

    static func viewsCount(_ count: String) -> String {
        loc("player.views_count", formatArgs: [count])
    }
    static var noRating: String { loc("player.no_rating") }
    static var ratingArrow: String { loc("player.rating_arrow") }
    static var playerNowPlaying: String { loc("player.now_playing") }
    static var playerNeedsUnlock: String { loc("player.needs_unlock") }
    static func playerUnlockedCount(_ count: Int) -> String { loc("player.unlocked_count", formatArgs: [count]) }
    static var unlockAllEpisodes: String { loc("player.unlock_all_episodes") }
    static var playerExitFullscreen: String { loc("player.exit_fullscreen") }
    static var playerFullscreen: String { loc("player.fullscreen") }
    static var playerLoadFailed: String { loc("player.load_failed") }
    static var tabIntroduction: String { loc("player.tab_introduction") }
    static var tabEpisodes: String { loc("player.tab_episodes") }
    static var castAndCrew: String { loc("player.cast_and_crew") }
    static var moreSimilar: String { loc("player.more_similar") }
    static var collapse: String { loc("player.collapse") }
    static var shareText: String { loc("player.share") }
    static var shareReward: String { loc("player.share_reward") }
    static var copyLink: String { loc("player.copy_link") }
    static var playerSpeed: String { loc("player.speed") }
    static var playbackSettings: String { loc("player.playback_settings") }
    static var currentResolution: String { loc("player.current_resolution") }
    static var pictureInPicture: String { loc("player.picture_in_picture") }
    static var subtitleFeedbackPrefix: String { loc("player.subtitle_feedback_prefix") }
    static var subtitleFeedbackLink: String { loc("player.subtitle_feedback_link") }
    static func playerEpisodeNumber(_ num: Int) -> String {
        loc("player.episode_number", formatArgs: [num])
    }

    // MARK: - Episode

    static func totalEpisodeCount(_ count: Int) -> String {
        loc("episode.total_count", formatArgs: [count])
    }

    // MARK: - Splash

    static var splashTagline: String { loc("splash.tagline") }

    // MARK: - Login

    static var loginTitle: String { loc("login.title") }
    static var loginTagline: String { loc("login.tagline") }
    static var loginGoogleButton: String { loc("login.google_button") }
    static var loginAppleButton: String { loc("login.apple_button") }
    static var loginFacebookButton: String { loc("login.facebook_button") }
    static var loginGuestButton: String { loc("login.guest_button") }
    static var loginAgreementPrefix: String { loc("login.agreement_prefix") }
    static var loginTermsOfService: String { loc("login.terms_of_service") }
    static var loginAnd: String { loc("login.and") }
    static var loginPrivacyPolicy: String { loc("login.privacy_policy") }
    static var loginPeriod: String { loc("login.period") }

    // MARK: - Episode Lock

    static func episodeLockedHint(_ ep: Int) -> String {
        loc("episode.locked_hint", formatArgs: [ep])
    }
    static func episodeUnlockWithCoinsHint(_ cost: Int) -> String {
        loc("episode.unlock_with_coins_hint", formatArgs: [cost])
    }
    static func episodeUnlockButton(_ cost: Int) -> String {
        loc("episode.unlock_button", formatArgs: [cost])
    }
    static var episodeSkipUnlock: String { loc("episode.skip_unlock") }
    static var episodeUnlockSuccess: String { loc("episode.unlock_success") }
    static func episodeLockTitle(_ ep: Int) -> String {
        loc("episode.lock_title", formatArgs: [ep])
    }
    static func episodeUnlockCost(_ cost: Int) -> String {
        loc("episode.unlock_cost", formatArgs: [cost])
    }
    static func unlockWithCoins(_ cost: Int) -> String {
        loc("episode.unlock_with_coins", formatArgs: [cost])
    }
    static var vipFreeWatch: String { loc("episode.vip_free_watch") }
    static func insufficientCoinsRecharge(_ balance: Int) -> String {
        loc("episode.insufficient_coins", formatArgs: [balance])
    }

    // MARK: - Coin Purchase

    static var buyCoins: String { loc("coin.buy_coins") }
    static var coinsUnit: String { loc("coin.coins_unit") }
    static func bonusCoins(_ n: Int) -> String {
        loc("coin.bonus_coins", formatArgs: [n])
    }
    static var buyNow: String { loc("coin.buy_now") }
    static var purchasing: String { loc("coin.purchasing") }
    static var purchaseSuccess: String { loc("coin.purchase_success") }

    // MARK: - My List (Task31)

    static var myListLoginGuide: String { loc("my_list.login_guide") }
    static var myListFollowing: String { loc("my_list.following") }
    static var myListHistory: String { loc("my_list.history") }
    static var myListChoose: String { loc("my_list.choose") }
    static var myListRemove: String { loc("my_list.remove") }
    static var myListMostTrending: String { loc("my_list.most_trending") }
    static var myListEmptyFollowing: String { loc("my_list.empty_following") }
    static var myListEmptyHistory: String { loc("my_list.empty_history") }
    static var myListLoadFailed: String { loc("my_list.load_failed") }
    static var myListPartialRemoveFailed: String { loc("my_list.partial_remove_failed") }

    // Re-export common keys for convenience
    static var myListSignIn: String { loc("my_list.sign_in") }
    static func myListEpisodeProgress(_ current: Int, _ total: Int) -> String {
        loc("my_list.episode_progress", formatArgs: [current, total])
    }
    static var myListSelectionSelected: String { loc("my_list.selection_selected") }
    static var myListSelectionUnselected: String { loc("my_list.selection_unselected") }
    static func myListRemoveSelectedCount(_ count: Int) -> String {
        loc("my_list.remove_selected_count", formatArgs: [count])
    }
    static var myListNoMoreContent: String { loc("my_list.no_more_content") }

    static var commonRetry: String { retry }
    static var commonCancel: String { cancel }
}
