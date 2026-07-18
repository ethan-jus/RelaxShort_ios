import SwiftUI

/// DramaBox 风格启动页：纯黑底 + 中心 logo + 名称 + tagline
struct SplashView: View {
    var onFinish: () -> Void
    var autoFinishAfter: TimeInterval? = 2

    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 中心品牌内容
            VStack(spacing: 20) {
                Spacer()

                // App 图标
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)

                // App 名称
                Text("RelaxShort")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)

                // Tagline
                Text(L10n.splashTagline)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)

                Spacer()

                // 底部品牌文字
                Text("RelaxShort")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(4)
                    .textCase(.uppercase)
                    .padding(.bottom, 40)
            }
        }
        .opacity(opacity)
        .statusBarHidden(true)
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) { opacity = 1 }
            if let autoFinishAfter {
                DispatchQueue.main.asyncAfter(deadline: .now() + autoFinishAfter) {
                    onFinish()
                }
            }
        }
    }
}

#if DEBUG
struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView(onFinish: {})
            .preferredColorScheme(.dark)
    }
}
#endif
