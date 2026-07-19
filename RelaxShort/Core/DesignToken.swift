import SwiftUI

// MARK: - DesignToken

/// RelaxShort 全局设计令牌系统
/// 参照 UI 实现规范 第1节 & 第8节，支持深色/浅色双主题
enum DT {
    
    // MARK: - Colors 色彩系统
    
    /// App 唯一品牌强调色：Logo 红。
    static let logoRed        = SwiftUI.Color(hex: "#E85048")
    /// 历史命名兼容。所有旧 pink 调用统一落到 Logo 红，禁止继续产生粉色分支。
    static let brandPink      = logoRed
    /// 历史深色命名兼容；当前设计系统不再使用另一套粉色。
    static let brandPinkDark  = logoRed
    /// 硬币/金币 #C29852
    static let brandGold      = SwiftUI.Color(hex: "#C29852")
    /// 会员卡金色 #D6B46A
    static let memberGold     = SwiftUI.Color(hex: "#D6B46A")
    /// 金币色（耀眼金） #F5C842
    static let coinGold       = SwiftUI.Color(hex: "#F5C842")
    /// 待领取奖励胶囊背景（暗酒红）
    static let rewardBadgeBackground = SwiftUI.Color(hex: "#281516")
    /// 待领取奖励胶囊描边
    static let rewardBadgeBorder = SwiftUI.Color(hex: "#7A3434")
    /// 待领取奖励胶囊文字（暖金）
    static let rewardBadgeText = SwiftUI.Color(hex: "#E7BE69")
    
    /// 功能色
    /// 爆款角标 #FF3B30
    static let hotTag         = SwiftUI.Color(hex: "#FF3B30")
    /// 成功/已购 #34C759
    static let success        = SwiftUI.Color(hex: "#34C759")
    /// 通知红点 #FF3B30
    static let badgeRed       = SwiftUI.Color(hex: "#FF3B30")
    
    /// 首页顶部暖棕区域 #6B5F43 (仅 dark mode)
    static let bgHomeHeader   = SwiftUI.Color(hex: "#6B5F43")

    /// 排名页渐变起始 (橙) #FF9500
    static let rankGradientStart = SwiftUI.Color(hex: "#FF9500")
    /// 排名页渐变中间使用 App Logo 红。
    static let rankGradientMid   = logoRed
    
    // MARK: - Color (Theme-aware 语义色)
    
    /// 主题感知颜色 — 所有背景/文字/UI色由此统一管理
    enum Color {
        // 背景色
        /// 全局主背景 — dark: #000000, light: #F5F5F5
        static let bgPrimary: SwiftUI.Color = {
            colorFor(light: "#F5F5F5", dark: "#000000")
        }()
        /// 卡片/列表项底色 — dark: #1A1A1A, light: #FFFFFF
        static let bgCard: SwiftUI.Color = {
            colorFor(light: "#FFFFFF", dark: "#1A1A1A")
        }()
        /// 分割线 — dark: #111111, light: #E5E5E5
        static let bgDivider: SwiftUI.Color = {
            colorFor(light: "#E5E5E5", dark: "#111111")
        }()
        /// 弹窗底色 — dark: #111111, light: #FFFFFF
        static let bgModal: SwiftUI.Color = {
            colorFor(light: "#FFFFFF", dark: "#111111")
        }()
        
        // 文字色
        /// 主文字 — dark: #FFFFFF, light: #1A1A1A
        static let textPrimary: SwiftUI.Color = {
            colorFor(light: "#1A1A1A", dark: "#FFFFFF")
        }()
        /// 辅助文字 — dark: #999999, light: #666666
        static let textSecondary: SwiftUI.Color = {
            colorFor(light: "#666666", dark: "#999999")
        }()
        /// 次要文字/禁用态 — dark: #666666, light: #999999
        static let textTertiary: SwiftUI.Color = {
            colorFor(light: "#999999", dark: "#666666")
        }()
        
        // 封面占位渐变
        static let bgCoverPlaceholderStart    = SwiftUI.Color(hex: "#161616")
        static let bgCoverPlaceholderEnd      = SwiftUI.Color(hex: "#09090B")
        static let bgCoverPlaceholderAltStart = SwiftUI.Color(hex: "#1A1A1D")
        static let bgCoverPlaceholderAltEnd   = SwiftUI.Color(hex: "#101012")

        /// 半透明白色覆盖 — dark: white.opacity(0.05), light: black.opacity(0.05)
        static let overlaySubtle: SwiftUI.Color = {
            colorFor(light: SwiftUI.Color(hex: "#000000").opacity(0.05),
                     dark: SwiftUI.Color(hex: "#FFFFFF").opacity(0.05))
        }()
        
        /// 半透明覆盖 medium — dark: white.opacity(0.14), light: black.opacity(0.08)
        static let overlayMedium: SwiftUI.Color = {
            colorFor(light: SwiftUI.Color(hex: "#000000").opacity(0.08),
                     dark: SwiftUI.Color(hex: "#FFFFFF").opacity(0.14))
        }()
    }
    
    // MARK: - Theme-aware Color Helper
    
    /// 根据当前 colorScheme 返回对应颜色
    /// 直接读取 UserDefaults 以避免跨 actor 隔离警告
    private static func colorFor(light hexLight: String, dark hexDark: String) -> SwiftUI.Color {
        let themeRaw = UserDefaults.standard.string(forKey: "app.themeMode")
        let mode = themeRaw.flatMap(ThemeMode.init(rawValue:)) ?? .dark
        switch mode {
        case .light:
            return SwiftUI.Color(hex: hexLight)
        case .dark, .system:
            return SwiftUI.Color(hex: hexDark)
        }
    }

    private static func colorFor(light: SwiftUI.Color, dark: SwiftUI.Color) -> SwiftUI.Color {
        let themeRaw = UserDefaults.standard.string(forKey: "app.themeMode")
        let mode = themeRaw.flatMap(ThemeMode.init(rawValue:)) ?? .dark
        switch mode {
        case .light: return light
        case .dark, .system: return dark
        }
    }
    
    // MARK: - Font 字体系统
    
    /// 字体系统 — 基于 PingFang SC / SF Pro Display
    enum Font {
        /// 大标题 (页面标题) — PingFang SC 28pt .bold
        static let largeTitle: SwiftUI.Font = .system(size: 28, weight: .bold)
        /// Section 标题 — PingFang SC 22pt .bold
        static let sectionTitle: SwiftUI.Font = .system(size: 22, weight: .bold)
        /// 副标题 — PingFang SC 18pt .semibold
        static let subtitle: SwiftUI.Font = .system(size: 18, weight: .semibold)
        /// 正文 — PingFang SC 15pt .regular
        static let bodyDefault: SwiftUI.Font = .system(size: 15, weight: .regular)
        /// 辅助文字/标签 — PingFang SC 13pt .regular
        static let caption: SwiftUI.Font = .system(size: 13, weight: .regular)
        /// 小字 (热度/提示) — PingFang SC 11pt .regular
        static let small: SwiftUI.Font = .system(size: 11, weight: .regular)
        /// Tab 标签文字 — PingFang SC 10pt .medium
        static let tabLabel: SwiftUI.Font = .system(size: 10, weight: .medium)
        /// 按钮文字 — PingFang SC 16pt .bold
        static let button: SwiftUI.Font = .system(size: 16, weight: .bold)
        /// 价格数字 — SF Pro Display 28pt .heavy
        static let priceNumber: SwiftUI.Font = .system(size: 28, weight: .heavy)
        /// 价格单位 — PingFang SC 14pt .medium
        static let priceUnit: SwiftUI.Font = .system(size: 14, weight: .medium)
        /// 空状态图标字体
        static let emptyIcon: SwiftUI.Font = .system(size: 36, weight: .regular)
        /// icon 标准尺寸
        static let icon22: SwiftUI.Font = .system(size: 22)
        static let icon20: SwiftUI.Font = .system(size: 20)

        /// 动态字体 — 大标题 (可变尺寸 & 字重，默认 .bold)
        static func largeTitle(_ size: CGFloat, weight: SwiftUI.Font.Weight = .bold) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
        /// 动态字体 — 正文 (可变尺寸 & 字重)
        static func body(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight)
        }
    }
    
    // MARK: - Space 间距系统
    
    /// 8pt 网格间距系统
    enum Space {
        /// 标签内间距 4pt
        static let xs: CGFloat = 4
        /// 紧密元素间距 8pt
        static let sm: CGFloat = 8
        /// 标准元素间距 12pt
        static let md: CGFloat = 12
        /// 区块内间距 16pt
        static let lg: CGFloat = 16
        /// 区块间距 20pt
        static let xl: CGFloat = 20
        /// 大区块间距 24pt
        static let xxl: CGFloat = 24
        /// 页面水平边距 16pt
        static let pageH: CGFloat = 16
        /// 卡片内水平 padding 12pt
        static let cardH: CGFloat = 12
    }
    
    // MARK: - Radius 圆角系统
    
    /// 统一圆角半径
    enum Radius {
        /// 角标/标签 4pt
        static let sm: CGFloat = 4
        /// 卡片/按钮 8pt
        static let md: CGFloat = 8
        /// 大卡片/Banner 12pt
        static let lg: CGFloat = 12
        /// 弹窗 16pt
        static let xl: CGFloat = 16
        /// 胶囊按钮/头像 9999pt (全圆)
        static let full: CGFloat = 9999
    }
    
    // MARK: - Layout 尺寸常量
    
    /// 全局布局尺寸常量
    enum Layout {
        /// 底部 Tab Bar 高度 (含 safe area) 70pt
        static let tabBarHeight: CGFloat = 50
        /// Tab 图标尺寸 24pt
        static let tabIconSize: CGFloat = 24
        /// 竖版海报比例 2:3
        static let cardAspectRatio: CGFloat = 2.0 / 3.0
        /// 封面图高度 (宽约 140pt) ~210pt
        static let coverHeight: CGFloat = 210
        /// Banner 比例 16:9
        static let bannerAspectRatio: CGFloat = 16.0 / 9.0
        /// 搜索栏高度 40pt
        static let searchBarHeight: CGFloat = 40
        /// 胶囊搜索框高度 36pt
        static let capsuleSearchHeight: CGFloat = 36
        /// CTA 按钮高度 48pt
        static let ctaButtonHeight: CGFloat = 48
        /// 首页搜索头部总高 (含状态栏) ~104pt
        static let toolHeaderHeight: CGFloat = 104
    }
}

// MARK: - DramaBox 第一版复刻专用令牌

/// DramaBox 第一版复刻令牌 — 不替换 DT，只在复刻页面使用
enum DB {
    // MARK: 品牌色
    /// DramaBox 风格强调色统一使用 App Logo 红，避免界面混入额外高饱和粉色
    static let pink: SwiftUI.Color = DT.logoRed
    /// App Logo 主红色，用于选中态品牌色
    static let logoRed: SwiftUI.Color = DT.logoRed
    /// 金色/会员色 #C29852
    static let gold: SwiftUI.Color = SwiftUI.Color(hex: "#C29852")
    /// 纯黑背景
    static let black: SwiftUI.Color = .black
    /// 面板底色 #1A1A1A
    static let panel: SwiftUI.Color = SwiftUI.Color(hex: "#1A1A1A")
    /// 浮层面板底色 #222222
    static let panelElevated: SwiftUI.Color = SwiftUI.Color(hex: "#222222")
    /// 分割线 #2A2A2A
    static let divider: SwiftUI.Color = SwiftUI.Color(hex: "#2A2A2A")
    /// 弱化文字 #888888
    static let mutedText: SwiftUI.Color = SwiftUI.Color(hex: "#888888")
    /// 非选中态图标/文字
    static let unselected: SwiftUI.Color = SwiftUI.Color(hex: "#999999")

    // MARK: 布局尺寸
    /// 底部 Tab 栏高度 (含 safe area padding)
    static let bottomBarHeight: CGFloat = 64
    /// 弹层圆角 16pt
    static let sheetCornerRadius: CGFloat = 16
    /// 视频海报圆角 2pt，所有剧集封面统一使用这个值
    static let posterRadius: CGFloat = 2
    /// 卡片圆角 8pt
    static let cardRadius: CGFloat = 8
    /// CTA 按钮圆角 4pt
    static let ctaRadius: CGFloat = 4
    /// 海报宽度 (一行3列) ≈ 108pt
    static let posterWidth: CGFloat = 108
    /// 海报高度 2:3 ≈ 162pt
    static let posterHeight: CGFloat = 162
}

// MARK: - Color Extension

extension SwiftUI.Color {
    /// 通过十六进制字符串创建 Color
    /// - Parameter hex: 支持 `#RGB`, `#RRGGBB`, `#RRGGBBAA` 格式
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB -> RRGGBB (each digit repeated)
            (a, r, g, b) = (255, ((int >> 8) & 0xF) * 17, ((int >> 4) & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
