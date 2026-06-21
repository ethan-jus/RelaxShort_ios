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
