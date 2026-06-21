import SwiftUI

/// 字幕渲染 overlay
struct SubtitleRenderer: View { let text: String?
    var body: some View {
        if let text, !text.isEmpty { VStack { Spacer(); Text(text).font(.system(size: 16, weight: .semibold)).foregroundColor(.white).shadow(color: .black.opacity(0.7), radius: 2).multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 60) } }
    }
}
