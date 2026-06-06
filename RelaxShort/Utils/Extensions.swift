import SwiftUI

// MARK: - View Extensions for reusable styles
extension View {
    func dramaCardStyle() -> some View {
        self
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    func dramaButtonStyle() -> some View {
        self
            .background(DT.brandPink)
            .cornerRadius(24)
            .foregroundColor(DT.Color.textPrimary)
    }
}

// MARK: - Safe Area Helpers (replaces deprecated UIScreen.main)

extension UIApplication {
    /// 获取当前 key window 的 safe area insets
    static var safeAreaInsets: UIEdgeInsets {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        }
        return window.safeAreaInsets
    }

    /// 屏幕尺寸 (replaces UIScreen.main.bounds)
    static var screenSize: CGSize {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return CGSize(width: 390, height: 844)
        }
        return windowScene.screen.bounds.size
    }

    /// 屏幕 scale (replaces UIApplication.screenScale)
    static var screenScale: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return 3.0
        }
        return windowScene.screen.scale
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// 跳转到 VIP 页面
    static let navigateToVIP = Notification.Name("com.relaxshort.navigateToVIP")
    /// 弹出金币购买页
    static let showCoinPurchase = Notification.Name("com.relaxshort.showCoinPurchase")
    /// 全屏弹出搜索页（无 TabBar）
    static let showSearch = Notification.Name("com.relaxshort.showSearch")
    /// 全屏弹出会员页（无 TabBar）
    static let showMembership = Notification.Name("com.relaxshort.showMembership")
    /// 全屏弹出金币福利页（无 TabBar）
}
