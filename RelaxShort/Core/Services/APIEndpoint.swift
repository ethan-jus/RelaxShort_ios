import Foundation

// MARK: - HTTP Method

/// RESTful HTTP 请求方法
enum HTTPMethod: String {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case delete = "DELETE"
    case patch  = "PATCH"
}

// MARK: - APIEndpoint

/// 定义所有 RelaxShort API 端点。
/// 包含真实后端 `/api/v2/**` 路径 + 旧 mock 路径（保留兼容）。
enum APIEndpoint {

    // MARK: - 真实 v2 端点

    /// App 冷启动初始化
    case appInit
    /// For You 推荐流（cursor 分页）
    case forYou(cursor: String?, limit: Int, contentLanguage: String?, countryCode: String?)
    /// 某部短剧的所有剧集
    case seriesEpisodes(seriesId: String)
    /// 剧集播放地址
    case episodePlay(episodeId: String)

    // MARK: - Task15 第二批 v2 端点

    case home(contentLanguage: String?, countryCode: String?)
    case searchDefault(contentLanguage: String?, countryCode: String?)
    case searchV2(query: String, cursor: String?, limit: Int, contentLanguage: String?, countryCode: String?)
    case rankings(type: String, contentLanguage: String?, countryCode: String?)
    case categories(contentLanguage: String?, countryCode: String?)
    case categorySeries(categoryCode: String, cursor: String?, limit: Int, contentLanguage: String?, countryCode: String?)

    // MARK: - 旧 mock 端点（保留兼容）

    case homeFeed(category: DramaCategory)
    case banners
    case dramaDetail(id: String)
    case episodes(dramaId: String)
    case watchHistory(page: Int)
    case updateProgress(dramaId: String, episode: Int, seconds: Double)
    case userProfile
    case updateProfile(nickname: String?, avatar: String?)
    case subscribe(plan: String)
    case subscriptionStatus
    case bookmarks(page: Int)
    case addBookmark(dramaId: String)
    case removeBookmark(dramaId: String)
    case coinTransactions(page: Int)
    case purchaseCoins(packageId: String)
    case search(keyword: String, page: Int)
    case login(phone: String, code: String)
    case logout
}

// MARK: - Endpoint Configuration

extension APIEndpoint {

    /// 真实后端 baseURL
    var baseURL: String {
        switch self {
        case .appInit, .forYou, .seriesEpisodes, .episodePlay,
             .home, .searchDefault, .searchV2, .rankings, .categories, .categorySeries:
            return APIConfig.baseURL
        default:
            return "https://mock.relaxshort.local/v1"
        }
    }

    /// 请求路径
    var path: String {
        switch self {
        // ── 真实 v2 ──
        case .appInit:                      return "/api/v2/app/init"
        case .forYou:                       return "/api/v2/feed/for-you"
        case .seriesEpisodes(let id):       return "/api/v2/series/\(id)/episodes"
        case .episodePlay(let id):          return "/api/v2/episodes/\(id)/play"
        // ── Task15 v2 ──
        case .home:                         return "/api/v2/home"
        case .searchDefault:                return "/api/v2/search/default"
        case .searchV2:                     return "/api/v2/search"
        case .rankings:                     return "/api/v2/rankings"
        case .categories:                   return "/api/v2/categories"
        case .categorySeries(let code, _, _, _, _): return "/api/v2/categories/\(code)/series"
        // ── 旧 mock ──
        case .homeFeed:                     return "/home/feed"
        case .banners:                      return "/home/banners"
        case .dramaDetail(let id):          return "/dramas/\(id)"
        case .episodes(let dramaId):        return "/dramas/\(dramaId)/episodes"
        case .watchHistory:                 return "/user/history"
        case .updateProgress:               return "/user/progress"
        case .userProfile:                  return "/user/profile"
        case .updateProfile:                return "/user/profile"
        case .subscribe:                    return "/vip/subscribe"
        case .subscriptionStatus:           return "/vip/status"
        case .bookmarks:                    return "/user/bookmarks"
        case .addBookmark:                  return "/user/bookmarks"
        case .removeBookmark(let id):       return "/user/bookmarks/\(id)"
        case .coinTransactions:             return "/user/coins/transactions"
        case .purchaseCoins:                return "/user/coins/purchase"
        case .search:                       return "/search"
        case .login:                        return "/auth/login"
        case .logout:                       return "/auth/logout"
        }
    }

    /// HTTP 方法
    var method: HTTPMethod {
        switch self {
        case .appInit:              return .post
        case .forYou, .seriesEpisodes, .episodePlay,
             .home, .searchDefault, .searchV2, .rankings, .categories, .categorySeries: return .get
        case .homeFeed, .banners, .dramaDetail, .episodes,
             .watchHistory, .userProfile, .subscriptionStatus,
             .bookmarks, .coinTransactions, .search: return .get
        case .updateProgress, .subscribe, .addBookmark,
             .purchaseCoins, .login: return .post
        case .updateProfile: return .patch
        case .removeBookmark, .logout: return .delete
        }
    }

    /// 请求头（统一注入）
    var headers: [String: String] {
        var base: [String: String] = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Platform": "ios",
            "X-Client-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "Accept-Language": Locale.preferredLanguages.first ?? "en"
        ]

        // App 启动后保存的语言上下文
        if let uiLang = UserDefaults.standard.string(forKey: "app_ui_language"), !uiLang.isEmpty {
            base["X-App-Language"] = uiLang
        }
        if let contentLang = UserDefaults.standard.string(forKey: "app_content_language"), !contentLang.isEmpty {
            // 在需要时作为 query 参数使用，不单独做 header
            _ = contentLang
        }
        if let country = UserDefaults.standard.string(forKey: "app_country_code"), !country.isEmpty {
            base["X-Region-Code"] = country
        }

        // 登录 token
        if let token = StorageService.shared.accessToken {
            base["Authorization"] = "Bearer \(token)"
        }
        return base
    }

    /// 请求体
    var body: Data? {
        switch method {
        case .get, .delete:
            return nil
        case .post, .put, .patch:
            break
        }

        let params: [String: Any]
        switch self {
        case .appInit:
            params = [:]
        case .homeFeed(let category):
            params = ["category": category.rawValue]
        case .watchHistory(let page):
            params = ["page": page, "pageSize": 20]
        case .updateProgress(let dramaId, let episode, let seconds):
            params = ["dramaId": dramaId, "episode": episode, "seconds": seconds]
        case .updateProfile(let nickname, let avatar):
            var dict: [String: String] = [:]
            if let nickname = nickname { dict["nickname"] = nickname }
            if let avatar = avatar { dict["avatar"] = avatar }
            params = dict
        case .subscribe(let plan):
            params = ["plan": plan, "platform": "ios"]
        case .addBookmark(let dramaId):
            params = ["dramaId": dramaId]
        case .purchaseCoins(let packageId):
            params = ["packageId": packageId, "platform": "ios"]
        case .search(let keyword, let page):
            params = ["keyword": keyword, "page": page, "pageSize": 20]
        case .login(let phone, let code):
            params = ["phone": phone, "code": code]
        default:
            params = [:]
        }
        guard !params.isEmpty || method == .post || method == .put || method == .patch else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: params, options: [])
    }

    /// 完整 URL（真实 v2 端点的 query 参数用 URLQueryItem）
    var url: URL? {
        var components = URLComponents(string: baseURL + path)

        switch self {
        case .forYou(let cursor, let limit, let contentLanguage, let countryCode):
            var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: "\(limit)")]
            if let c = cursor { items.append(URLQueryItem(name: "cursor", value: c)) }
            if let cl = contentLanguage { items.append(URLQueryItem(name: "content_language", value: cl)) }
            if let cc = countryCode { items.append(URLQueryItem(name: "country_code", value: cc)) }
            components?.queryItems = items
        case .search(let keyword, let page):
            components?.queryItems = [
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        case .seriesEpisodes:
            break
        case .episodePlay:
            break
        // ── Task15 v2 query params ──
        case .home(let cl, let cc):
            var items = [URLQueryItem]()
            if let c = cl { items.append(URLQueryItem(name: "content_language", value: c)) }
            if let c = cc { items.append(URLQueryItem(name: "country_code", value: c)) }
            if !items.isEmpty { components?.queryItems = items }
        case .searchDefault(let cl, let cc):
            var items = [URLQueryItem]()
            if let c = cl { items.append(URLQueryItem(name: "content_language", value: c)) }
            if let c = cc { items.append(URLQueryItem(name: "country_code", value: c)) }
            if !items.isEmpty { components?.queryItems = items }
        case .searchV2(let q, let cursor, let limit, let cl, let cc):
            var items = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "\(limit)")]
            if let c = cursor { items.append(URLQueryItem(name: "cursor", value: c)) }
            if let c = cl { items.append(URLQueryItem(name: "content_language", value: c)) }
            if let c = cc { items.append(URLQueryItem(name: "country_code", value: c)) }
            components?.queryItems = items
        case .rankings(let type, let cl, let cc):
            var items = [URLQueryItem(name: "type", value: type)]
            if let c = cl { items.append(URLQueryItem(name: "content_language", value: c)) }
            if let c = cc { items.append(URLQueryItem(name: "country_code", value: c)) }
            components?.queryItems = items
        case .categories(let cl, let cc):
            var items = [URLQueryItem]()
            if let c = cl { items.append(URLQueryItem(name: "content_language", value: c)) }
            if let c = cc { items.append(URLQueryItem(name: "country_code", value: c)) }
            if !items.isEmpty { components?.queryItems = items }
        case .categorySeries(_, let cursor, let limit, let cl, let cc):
            var items = [URLQueryItem(name: "limit", value: "\(limit)")]
            if let c = cursor { items.append(URLQueryItem(name: "cursor", value: c)) }
            if let c = cl { items.append(URLQueryItem(name: "content_language", value: c)) }
            if let c = cc { items.append(URLQueryItem(name: "country_code", value: c)) }
            components?.queryItems = items
        default:
            break
        }
        return components?.url
    }
}
