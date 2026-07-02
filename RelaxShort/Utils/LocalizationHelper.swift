import Foundation

// MARK: - L10n

/// 本地化便捷访问器
/// 所有 UI 字符串通过此枚举统一访问，支持中英文切换
///
/// 用法：
/// ```swift
/// Text(L10n.featured)
/// Text(L10n.checkedInDays(7))
/// ```
///
/// 双保险机制：
/// 1. 优先从 `Bundle.main` 的 Localizable.strings 读取翻译
/// 2. 若 .strings 未打包进 Bundle（如未加入 Xcode target），回退到硬编码的中文默认值
enum L10n {

    // MARK: - Fallback Dictionary (zh-Hans defaults)
    /// 当 NSLocalizedString 返回 raw key 时（.strings 未打包），使用此字典兜底。
    /// key → 简体中文翻译。覆盖所有 L10n 使用的 key。
    private static let zhFallback: [String: String] = [
        // General
        "general.more": "更多",
        "general.share": "分享",
        "general.comment": "评论",
        "general.download": "下载",
        "general.cancel": "取消",
        "general.confirm": "确认",
        "general.retry": "重试",
        "general.loading": "加载中...",
        "general.no_content": "暂无内容",
        "general.error": "错误",
        "general.ok": "确定",
        // Search
        "search.hot_search_tab": "热搜榜",
        "search.hot_play_tab": "热播榜",
        "search.new_drama_tab": "新剧榜",
        "search.no_hot_search": "暂无热搜",
        "search.no_hot_play": "暂无热播",
        "search.no_new_drama": "暂无新剧",
        "search.placeholder": "与君远相知，不道云海深",
        "search.no_results": "未找到相关剧集",
        "search.try_different_keyword": "换个关键词试试吧",
        "search.hint": "搜索剧名、分类或标签",
        "search.failed": "搜索失败，请重试。",
        "search.recent_searches": "最近搜索",
        "search.trending_searches": "热门搜索",
        "search.clear_history": "清除搜索记录",
        "search.clear_text": "清除搜索内容",
        "search.tab.top_searched": "热门搜索",
        "search.tab.most_trending": "热门趋势",
        "search.tab.new_releases": "最新上线",
        "search.rank_accessibility_format": "第%d名：%@",
        // Home
        "home.featured": "精选",
        "home.rankings": "排行榜",
        "home.you_are_watching": "你正在追",
        "home.view_all": "查看全部",
        "home.episode_count": "集",
        "home.no_anime": "暂无动漫内容",
        "home.search_placeholder": "莫言春度芳菲尽",
        // Rank
        "rank.search_placeholder": "好巧原来你也重来了",
        "rank.no_data": "暂无排行数据",
        // Coin
        "coin.tab": "奖励金币",
        "coin.member_points_tab": "会员积分",
        "coin.my_coins": "我的金币",
        "coin.rules": "规则",
        "coin.reward_rules": "奖励规则",
        "coin.checked_in_days": "已签到%d天",
        "coin.watch_ad_for_coins": "看广告获得 30 金币",
        "coin.earn_coins": "赚取金币",
        "coin.apple_disclaimer": "本活动与 Apple Inc.无关",
        "coin.daily_check_in": "每日签到",
        // Ad
        "ad.watch_ad_for_coins": "观看广告+%d金币",
        "ad.remaining_count": "今日还可观看%d次",
        "ad.limit_reached": "今日次数已用完",
        "ad.watch_now": "观看广告",
        "ad.watched_today": "已看完",
        "ad.skip": "跳过",
        "ad.label": "广告",
        "ad.seconds_remaining": "还剩%d秒即可获得奖励",
        "ad.please_keep_watching": "请继续观看广告以获得奖励",
        "ad.watch_ad_to_unlock": "🎬 观看广告免费解锁",
        "ad.reward_tip": "观看30秒广告即可获得金币",
        "ad.unlock_tip": "观看30秒广告即可免费解锁本集",
        "ad.load_failed": "广告加载失败\n请稍后重试",
        "ad.sponsored_label": "赞助内容",
        "ad.sponsored_content_1": "热门短剧推荐 — 每天更新",
        "ad.sponsored_content_2": "免费追剧神器 — 海量资源",
        "ad.sponsored_content_3": "小说改编短剧 — 每周上新",
        "ad.sponsored_content_4": "短剧互动社区 — 边看边聊",
        "ad.sponsored_subtitle_1": "发现更多精彩短剧",
        "ad.sponsored_subtitle_2": "随时随地免费看",
        "ad.sponsored_subtitle_3": "原汁原味网络小说",
        "ad.sponsored_subtitle_4": "加入千万追剧人",
        "ad.native_detail_title": "热门短剧排行榜 — 今日必看",
        "ad.native_detail_body": "每天精选热门短剧推荐，古装甜宠、现代言情、逆袭虐渣等多种类型全覆盖。\n\n免费观影，海量资源，随时随地畅享追剧体验。",
        "ad.learn_more": "了解更多",
        "ad.app_open_title": "热门短剧推荐",
        "ad.app_open_subtitle": "每日精选 · 海量热播短剧免费看",
        // Membership
        "membership.join": "加入会员",
        "membership.weekly": "周会员",
        "membership.monthly": "月会员",
        "membership.yearly": "年会员",
        "membership.discount": "折扣",
        "membership.join_now": "立即加入",
        "membership.recharge_info": "充值说明",
        "membership.service_agreement": "服务协议和隐私条款",
        "membership.weekly_detail": "前3周$12.99/周，然后$19.99/周",
        "membership.monthly_detail": "$39.99/月",
        "membership.yearly_detail": "$149.99/年",
        "membership.load_failed": "套餐数据加载失败",
        "membership.terms_1": "1. RelaxShort内有免费和付费内容。",
        "membership.terms_2": "2. 付费内容可以用金币解锁或购买会员观看，会员有效期内无限次观看。",
        "membership.terms_3": "3. 其他说明请参考App内提示，如有疑问请联系客服。",
        // Benefits
        "benefit.all_shows": "16,000+ 部剧集免费看\n每周稳定上新 100+ 部新剧",
        "benefit.download": "下载",
        "benefit.vip_shows": "会员专享剧",
        "benefit.themes": "会员专属主题",
        "benefit.quality": "1080p 画质",
        "benefit.gift": "赠送好友影片 每周3次机会",
        "benefit.friend_gift": "送好友会员 每周1次机会",
        "benefit.no_ads": "免广告",
        // VIP
        "vip.unlock_all": "解锁全部精彩内容",
        "vip.vip_expiry": "VIP 有效期至 %@",
        "vip.remaining_days": "剩余 %d 天",
        "vip.recommended": "推荐",
        "vip.subscribe_now": "立即订阅",
        "vip.renew": "续费会员",
        "vip.auto_renew_notice": "自动续费，可随时取消",
        "vip.why_join": "为什么加入会员？",
        "vip.title": "RelaxShort VIP",
        "vip.center": "会员中心",
        // Profile
        "profile.recharge_now": "立即充值",
        "profile.my_wallet": "我的钱包",
        "profile.welfare_center": "福利中心",
        "profile.watch_history": "观看历史",
        "profile.language": "语言",
        "profile.customer_service": "在线客服",
        "profile.simplified_chinese": "简体中文",
        "profile.feature_in_development": "功能开发中",
        "profile.drama": "剧集",
        "profile.daily_points": "每日",
        "profile.points": "积分",
        "profile.quality": "画质",
        "profile.followed_count": "已关注 %d",
        "profile.login_to_view": "登录后查看个人中心",
        "profile.login_to_sync": "登录后即可访问个人资料、钱包等功能",
        "profile.logout": "退出登录",
        "profile.confirm_logout": "确认退出",
        "profile.logout_confirm_message": "确定要退出登录吗？",
        // Favorites
        "favorites.my_favorites": "我的收藏",
        "favorites.no_watch_history": "暂无观看记录",
        "favorites.no_bookmarks": "暂无收藏内容",
        "favorites.login_to_view": "登录后查看收藏",
        "favorites.login_to_sync": "登录后即可同步你的收藏内容",
        "favorites.login_now": "立即登录",
        "favorites.continue_watching": "继续观看",
        "favorites.watch_now": "立即观看",
        "favorites.watched_percent": "已看 %d%%",
        "favorites.episode_progress": "第%d集 / %d集",
        "favorites.total_episodes": "共%d集",
        "favorites.save_your_list": "保存你的列表",
        "favorites.login_recommendation": "为了防止你的收藏列表丢失，\n强烈建议您进行登录",
        "favorites.login_google": "使用 Google 登录",
        "favorites.login_apple": "使用 Apple 登录",
        "favorites.login_agreement": "登录账户，您已阅读并同意我们的\n服务协议 & 隐私条款",
        "favorites.added_toast": "已收藏",
        "favorites.removed_toast": "已取消收藏",
        // Recommend
        "recommend.no_content": "暂无推荐内容",
        "recommend.load_failed": "推荐内容加载失败",
        "recommend.pull_to_refresh": "下拉刷新试试",
        "recommend.watch_full_series": "观看全集",
        "recommend.episode_number": "第%d集",
        "recommend.synopsis": "剧情简介",
        "player.expand": "展开",
        // Exit Guide
        "exit.new_drama_benefit": "新剧",
        "exit.reward_benefit": "奖励",
        "exit.promo_benefit": "活动优惠",
        "exit.enable_title": "开启通知，不错过更新",
        "exit.enable_body": "发现宝藏新剧，开启通知，为你推荐更多潜力佳作!",
        "exit.enable_button": "开启通知",
        "exit.skip_button": "暂不开启",
        // Shared
        "shared.total_episodes_prefix": "共",
        // Tags
        "tag.ceo": "总裁",
        "tag.romance": "言情",
        "tag.rebirth": "重生",
        "tag.revenge": "复仇",
        "tag.thriller": "悬疑",
        "tag.comics": "漫改",
        "tag.funny": "搞笑",
        "tag.billionaire": "豪门",
        "tag.ancient": "古装",
        "tag.modern": "现代",
        "tag.drama": "剧情",
        "tag.youth": "青春",
        "tag.strong-female": "大女主",
        "tag.family": "家庭",
        "tag.sweet": "甜宠",
        "tag.comedy": "喜剧",
        "tag.fantasy": "玄幻",
        "tag.power": "权谋",
        "tag.immortal": "仙侠",
        "tag.medical": "神医",
        "tag.urban": "都市",
        "tag.strong-male": "强男主",
        "tag.baby": "萌宝",
        "tag.fate": "命运",
        "tag.marriage": "婚恋",
        "tag.celebrity": "明星",
        "tag.divorce": "离婚",
        "tag.substitute": "替身",
        "tag.chase": "追妻",
        "tag.food": "美食",
        "tag.countryside": "乡村",
        "tag.poetry": "诗词",
        "tag.action": "动作",
        "tag.dark": "暗黑",
        "tag.contract": "契约",
        "tag.mystery": "悬疑",
        // Categories
        "category.总裁": "总裁",
        "category.逆袭": "逆袭",
        "category.玄幻": "玄幻",
        "category.古代言情": "古装",
        "category.现代言情": "现代",
        "category.豪门恩怨": "豪门",
        "category.马甲": "马甲",
        "category.甜宠": "甜宠",
        "category.都市": "都市",
        "category.古装": "古装",
        // English backend category names (Task20: prevent "category.Romance"-style display)
        "category.Romance": "Romance",
        "category.romance": "Romance",
        "category.Fantasy": "Fantasy",
        "category.fantasy": "Fantasy",
        "category.Thriller": "Thriller",
        "category.thriller": "Thriller",
        "category.Drama": "Drama",
        "category.drama": "Drama",
        "category.Action": "Action",
        "category.action": "Action",
        // Badge tag labels
        "badge.vip": "VIP",
        "badge.hot": "Hot",
        "badge.new": "New",
        "badge.trending": "Trending",
        // Theme
        "theme.system": "跟随系统",
        "theme.light": "浅色模式",
        "theme.dark": "深色模式",
        "theme.menu.title": "主题",
        "theme.sheet.title": "主题设置",
        // Language Names
        "lang.zh_hans": "简体中文",
        "lang.zh_hant": "繁體中文",
        "lang.en": "English",
        "lang.ko": "한국어",
        "lang.ja": "日本語",
        "lang.pt": "Português",
        "lang.es": "Español",
        "lang.ar": "العربية",
        // Tab Bar
        "home.tab.title": "首页",
        "recommend.tab.title": "推荐",
        "vip.tab.title": "会员",
        "favorites.tab.title": "收藏",
        "profile.tab.title": "我的",
        // Player
        "player.views_count": "%@ 次观看",
        "player.no_rating": "暂无评分",
        "player.rating_arrow": "评分 >",
        "player.tab_introduction": "简介",
        "player.tab_episodes": "选集",
        "player.cast_and_crew": "演职人员",
        "player.more_similar": "更多相似内容",
        "player.collapse": "收起",
        "player.share": "分享",
        "player.share_reward": "分享给第一位朋友，获得 10 金币",
        "player.copy_link": "复制链接",
        "player.speed": "倍速",
        "player.playback_settings": "播放设置",
        "player.current_resolution": "当前清晰度",
        "player.picture_in_picture": "画中画",
        "player.now_playing": "播放中",
        "player.needs_unlock": "需解锁",
        "player.unlocked_count": "· 已解锁 %d集",
        "player.subtitle_feedback_prefix": "字幕语言如有错漏，",
        "player.subtitle_feedback_link": "点击此处反馈",
        "player.unlock_all_episodes": "解锁全集",
        "player.exit_fullscreen": "退出全屏",
        "player.fullscreen": "全屏",
        "player.load_failed": "剧集加载失败",
        "player.episode_number": "第%d集",
        // Episode
        "episode.total_count": "共%d集",
        // Splash
        "splash.tagline": "短剧 · 无限放松",
        // Login
        "login.title": "RelaxShort",
        "login.tagline": "发现打动你的故事",
        "login.google_button": "使用 Google 登录",
        "login.apple_button": "使用 Apple 登录",
        "login.facebook_button": "使用 Facebook 登录",
        "login.guest_button": "游客登录",
        "login.agreement_prefix": "继续即表示您同意我们的 ",
        "login.terms_of_service": "服务条款",
        "login.and": " 和 ",
        "login.privacy_policy": "隐私政策",
        "login.period": "。",
        // Episode Lock
        "episode.lock_title": "第%d集已锁定",
        "episode.unlock_cost": "解锁需要 %d 金币",
        "episode.locked_hint": "第%d集 需要解锁",
        "episode.unlock_with_coins_hint": "消耗 %d 金币即可解锁本集",
        "episode.unlock_button": "%d 金币 立即解锁",
        "episode.skip_unlock": "暂不解锁",
        "episode.unlock_success": "解锁成功！",
        "episode.unlock_with_coins": "使用 %d 金币解锁",
        "episode.vip_free_watch": "VIP 免费看",
        "episode.insufficient_coins": "金币不足 (当前 %d)，充值即可解锁",
        // Coin Purchase
        "coin.buy_coins": "购买金币",
        "coin.coins_unit": "金币",
        "coin.bonus_coins": "加赠%d金币",
        "coin.buy_now": "立即购买",
        "coin.purchasing": "购买中...",
        "coin.purchase_success": "购买成功！",
    ]

    // MARK: - Core Lookup

    /// 双保险本地化查找：
    /// 1. 优先读取 Bundle.main 的 Localizable.strings
    /// 2. 若返回 raw key（.strings 未打包或 key 缺失），回退到硬编码中文
    private static func loc(_ key: String, formatArgs: [CVarArg] = []) -> String {
        let bundleValue = Bundle.main.localizedString(forKey: key, value: "\u{0010}FALLBACK\u{0010}", table: nil)
        let template: String
        if bundleValue == "\u{0010}FALLBACK\u{0010}" {
            // Not found in bundle — use hardcoded Chinese fallback
            template = zhFallback[key] ?? key
        } else {
            template = bundleValue
        }
        if formatArgs.isEmpty {
            return template
        }
        return String(format: template, arguments: formatArgs)
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
    static func followedCount(_ count: Int) -> String {
        loc("profile.followed_count", formatArgs: [count])
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
        String(format: loc("my_list.episode_progress"), current, total)
    }

    static var commonRetry: String { retry }
    static var commonCancel: String { cancel }
}
