import Foundation

// MARK: - Home Category

/// Home Categories tab 领域模型。脱离后端 DTO 和 UI 枚举。
/// - 真实模式：title 来自后端 categories 接口 `localizedName`
/// - Mock 模式：title 来自 `DramaCategory.rawValue`
struct HomeCategory: Identifiable {
    let id: String          // 后端 code（如 "romance"）或 DramaCategory.rawValue
    let code: String        // 后端 API code（categorySeries 用），Mock 时为 rawValue
    let title: String       // 展示文案
    let localCategory: DramaCategory?   // Mock 模式时关联的本地枚举，真实模式为 nil
}

/// 首页内容语言筛选项。启用范围和名称均来自后端语言目录，
/// 与 App 是否内置该语言的界面文案资源相互独立。
struct HomeContentLanguage: Identifiable, Equatable {
    let code: String
    let nameEn: String
    let nameNative: String

    var id: String { code }
    var displayName: String {
        if !nameNative.isEmpty { return nameNative }
        if !nameEn.isEmpty { return nameEn }
        return code
    }
}

/// 首页“猜你喜欢”中的真实分类合集。标题来自后端分类本地化，内容来自该分类的真实短剧接口。
struct HomeCategoryCollection: Identifiable {
    let category: HomeCategory
    let dramas: [DramaItem]

    var id: String { category.id + ":" + dramas.map(\.id).joined(separator: ",") }
    var title: String { category.title }
}
