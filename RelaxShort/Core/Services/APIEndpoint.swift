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

/// 定义所有 RelaxShort API 端点，包含完整的请求构建信息。
/// Phase 1 不接入真实后端，`baseURL` 指向本地 mock 域，
/// `makeMockResponse()` 提供离线测试数据。
enum APIEndpoint {

    // MARK: - 首页

    /// 获取首页推荐短剧列表
    /// - Parameter category: 短剧分类
    case homeFeed(category: DramaCategory)
    /// 获取首页 Banner 轮播数据
    case banners

    // MARK: - 详情 & 剧集

    /// 获取短剧详情
    /// - Parameter id: 短剧 ID
    case dramaDetail(id: String)
    /// 获取某部短剧的所有剧集列表
    /// - Parameter dramaId: 短剧 ID
    case episodes(dramaId: String)

    // MARK: - 观看记录

    /// 获取用户观看历史
    case watchHistory(page: Int)
    /// 上报观看进度
    case updateProgress(dramaId: String, episode: Int, seconds: Double)

    // MARK: - 用户

    /// 获取用户个人信息
    case userProfile
    /// 更新用户个人信息
    case updateProfile(nickname: String?, avatar: String?)

    // MARK: - VIP / 订阅

    /// 订阅 VIP 套餐
    /// - Parameter plan: 套餐 ID（如 "monthly", "yearly"）
    case subscribe(plan: String)
    /// 查询当前订阅状态
    case subscriptionStatus

    // MARK: - 书签 / 收藏

    /// 获取用户收藏列表
    case bookmarks(page: Int)
    /// 添加收藏
    case addBookmark(dramaId: String)
    /// 移除收藏
    case removeBookmark(dramaId: String)

    // MARK: - 金币 / 充值

    /// 获取金币交易记录
    case coinTransactions(page: Int)
    /// 购买金币
    case purchaseCoins(packageId: String)

    // MARK: - 搜索

    /// 搜索短剧
    case search(keyword: String, page: Int)

    // MARK: - 认证

    /// 手机号验证码登录
    case login(phone: String, code: String)
    /// 退出登录
    case logout
}

// MARK: - Endpoint Configuration

extension APIEndpoint {

    /// 基础地址（Phase 1 使用 mock host）
    var baseURL: String {
        "https://mock.relaxshort.local/v1"
    }

    /// 请求路径
    var path: String {
        switch self {
        case .homeFeed:             return "/home/feed"
        case .banners:              return "/home/banners"
        case .dramaDetail(let id):  return "/dramas/\(id)"
        case .episodes(let dramaId):return "/dramas/\(dramaId)/episodes"
        case .watchHistory:         return "/user/history"
        case .updateProgress:       return "/user/progress"
        case .userProfile:          return "/user/profile"
        case .updateProfile:        return "/user/profile"
        case .subscribe:            return "/vip/subscribe"
        case .subscriptionStatus:   return "/vip/status"
        case .bookmarks:            return "/user/bookmarks"
        case .addBookmark:          return "/user/bookmarks"
        case .removeBookmark(let id):return "/user/bookmarks/\(id)"
        case .coinTransactions:     return "/user/coins/transactions"
        case .purchaseCoins:         return "/user/coins/purchase"
        case .search:               return "/search"
        case .login:                return "/auth/login"
        case .logout:               return "/auth/logout"
        }
    }

    /// HTTP 方法
    var method: HTTPMethod {
        switch self {
        case .homeFeed, .banners, .dramaDetail, .episodes,
             .watchHistory, .userProfile, .subscriptionStatus,
             .bookmarks, .coinTransactions, .search:
            return .get
        case .updateProgress, .subscribe, .addBookmark,
             .purchaseCoins, .login:
            return .post
        case .updateProfile:
            return .patch
        case .removeBookmark, .logout:
            return .delete
        }
    }

    /// 请求头
    var headers: [String: String] {
        var base: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Client-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            "X-Platform": "iOS"
        ]
        // 如果本地存储了 token，自动注入 Authorization 头
        if let token = StorageService.shared.accessToken {
            base["Authorization"] = "Bearer \(token)"
        }
        return base
    }

    /// 请求体（JSON 编码为 Data）
    var body: Data? {
        let params: [String: Any]
        switch self {
        case .homeFeed(let category):
            params = ["category": category.rawValue]
        case .watchHistory(let page):
            params = ["page": page, "pageSize": 20]
        case .updateProgress(let dramaId, let episode, let seconds):
            params = [
                "dramaId": dramaId,
                "episode": episode,
                "seconds": seconds
            ]
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
        return try? JSONSerialization.data(withJSONObject: params, options: [])
    }

    /// 完整的 URL
    var url: URL? {
        var components = URLComponents(string: baseURL + path)

        // 部分 GET 请求使用 query parameters
        switch self {
        case .banners:
            break // 无额外 query
        case .search(let keyword, let page):
            components?.queryItems = [
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        default:
            break
        }

        return components?.url
    }
}
