import SwiftUI
import UIKit

// MARK: - Guest Identity

/// 将 Keychain 中稳定的安装 ID 转为适合页面展示的游客短 ID。
/// 该值只用于识别当前安装，不冒充后端用户 ID。
enum ProfileGuestIdentity {
    static func shortID(from installID: String) -> String {
        let compactID = installID
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        return String(compactID.prefix(8))
    }
}

// MARK: - Profile Identity Header

/// 顶部用户信息区。设置入口独占顶部行，用户 ID 与收藏数量并排展示。
struct ProfileIdentityHeader: View {
    let avatarURL: String?
    let title: String
    let displayID: String
    let favoriteCount: Int
    let isGuest: Bool
    let isVIP: Bool
    let onTap: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Image("ProfileRedLight")
                .resizable()
                .scaledToFill()
                .frame(height: 166)
                .offset(x: -6, y: -12)
                .blur(radius: 4)
                .opacity(0.62)
                .blendMode(.screen)
                .allowsHitTesting(false)

            VStack(spacing: DT.Space.sm) {
                HStack {
                    Spacer()
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("profile.settings".localized)
                }
                .frame(height: 44)

                HStack(alignment: .center, spacing: DT.Space.lg) {
                    Button(action: onTap) {
                        ProfileAvatarView(
                            url: avatarURL,
                            initials: String(title.prefix(2)).uppercased(),
                            size: 82,
                            showsGuestIcon: isGuest
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: DT.Space.sm) {
                        Button(action: onTap) {
                            HStack(spacing: 7) {
                                Text(title)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                if isGuest {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white.opacity(0.92))
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 7) {
                            HStack(spacing: 3) {
                                Text("ID \(displayID)")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                    .layoutPriority(1)
                                CopyIDButton(displayID: displayID)
                            }

                            Rectangle()
                                .fill(.white.opacity(0.18))
                                .frame(width: 1, height: 15)

                            HStack(spacing: 5) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(L10n.favoriteCount(favoriteCount))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))

                        if isVIP {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                Text("VIP")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(DT.memberGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DT.memberGold.opacity(0.14))
                            .clipShape(Capsule())
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, DT.Space.xl)
        }
        .frame(height: 166)
        .clipped()
    }
}

private struct CopyIDButton: View {
    let displayID: String
    @State private var didCopy = false

    var body: some View {
        Button {
            UIPasteboard.general.string = displayID
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "square.on.square")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(didCopy ? DT.memberGold : .white.opacity(0.72))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("profile.copy_id".localized)
    }
}

// MARK: - Profile Avatar

struct ProfileAvatarView: View {
    let url: String?
    let initials: String
    let size: CGFloat
    var showsGuestIcon = false

    var body: some View {
        Group {
            if let avatarURL = url, !avatarURL.isEmpty {
                CoverImageView(
                    url: avatarURL,
                    aspectRatio: 1.0,
                    cornerRadius: size / 2,
                    width: size,
                    height: size
                )
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#202124"), Color(hex: "#0D0E10")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: size, height: size)
                    if showsGuestIcon {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                            .offset(y: size * 0.04)
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
        .overlay(
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Profile Membership Card

/// 会员主视觉：电影感红黑渐变、金色皇冠资产和四项核心权益。
struct ProfileMembershipCard: View {
    let isVIP: Bool
    let vipExpireDate: Date?
    let onJoin: () -> Void

    private var expiryText: String {
        guard let date = vipExpireDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return String(format: "profile.membership_active_until".localized, formatter.string(from: date))
    }

    private var memberGold: Color { DT.memberGold }
    private var benefitText: Color { Color(hex: "#E3C98B") }
    private var subtitleGray: Color { Color.white.opacity(0.68) }

    var body: some View {
        VStack(spacing: DT.Space.sm) {
            HStack(spacing: DT.Space.sm) {
                Image("ProfileVIPCrown")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 68)
                    .blendMode(.screen)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(isVIP ? "profile.membership_active".localized : "profile.join_membership".localized)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(memberGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                    Text(isVIP ? expiryText : "vip.unlock_all".localized)
                        .font(.system(size: 12))
                        .foregroundColor(subtitleGray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                if isVIP {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("VIP")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(Color(hex: "#2A1603"))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(memberGold)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Text("profile.join_action".localized)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(DT.logoRed)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(height: 72)

            HStack(spacing: 0) {
                membershipBenefit(icon: "play.rectangle", text: "profile.membership_benefit_series".localized)
                benefitDivider
                membershipBenefit(icon: "gift", text: "profile.membership_benefit_points".localized)
                benefitDivider
                membershipBenefit(icon: "arrow.down.to.line", text: "profile.membership_benefit_download".localized)
                benefitDivider
                HDBenefitView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "#350B09"),
                        Color(hex: "#180504"),
                        Color(hex: "#030303")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.78),
                        Color.black.opacity(0.22),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RadialGradient(
                    colors: [DT.logoRed.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 220
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DT.logoRed.opacity(0.48), lineWidth: 1)
        )
        .shadow(color: DT.logoRed.opacity(0.16), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onJoin)
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, DT.Space.pageH)
    }

    private func membershipBenefit(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(memberGold)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(benefitText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
    }

    private var benefitDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 44)
    }
}

/// 自定义 HD 文字徽章，弥补 SF Symbols 的缺失。
private struct HDBenefitView: View {
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(DT.memberGold, lineWidth: 1.5)
                    .frame(width: 30, height: 20)
                Text("HD")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(DT.memberGold)
            }
            Text("profile.membership_benefit_quality".localized)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "#E3C98B"))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Profile Menu Card

struct ProfileMenuCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, DT.Space.lg)
    }
}

// MARK: - Profile Menu Row

struct ProfileMenuRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let subtitleIcon: String?
    let subtitleIconColor: Color
    let showsDivider: Bool
    let onTap: () -> Void

    init(
        icon: String,
        iconColor: Color = .white,
        title: String,
        subtitle: String? = nil,
        subtitleIcon: String? = nil,
        subtitleIconColor: Color = DT.coinGold,
        showsDivider: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.subtitleIcon = subtitleIcon
        self.subtitleIconColor = subtitleIconColor
        self.showsDivider = showsDivider
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DT.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundColor(iconColor)
                    .frame(width: 28)

                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                if let sub = subtitle {
                    if let sIcon = subtitleIcon {
                        Image(systemName: sIcon)
                            .font(.system(size: 14))
                            .foregroundColor(subtitleIconColor)
                    }
                    Text(sub)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.48))
                    .frame(width: 20)
            }
            .padding(.horizontal, DT.Space.md)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)

        if showsDivider {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.leading, 52)
                .padding(.trailing, 44)
        }
    }
}

// MARK: - Skeleton & Error States

struct ProfileHeaderSkeleton: View {
    var body: some View {
        ZStack(alignment: .top) {
            Image("ProfileRedLight")
                .resizable()
                .scaledToFill()
                .frame(height: 166)
                .offset(x: -6, y: -12)
                .blur(radius: 4)
                .opacity(0.62)
                .blendMode(.screen)

            VStack(spacing: DT.Space.sm) {
                HStack {
                    Spacer()
                    Circle()
                        .fill(DB.panelElevated)
                        .frame(width: 36, height: 36)
                        .padding(4)
                }
                .frame(height: 44)

                HStack(spacing: DT.Space.lg) {
                    Circle()
                        .fill(DB.panelElevated)
                        .frame(width: 82, height: 82)
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DB.panelElevated)
                            .frame(width: 120, height: 22)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DB.panelElevated)
                            .frame(width: 170, height: 13)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, DT.Space.xl)
        }
        .frame(height: 166)
        .clipped()
    }
}

struct ProfileInlineError: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(DT.logoRed)
            Text(message)
                .font(DT.Font.caption)
                .foregroundColor(DT.Color.textSecondary)
            Spacer()
            Button(action: onRetry) {
                Text(L10n.commonRetry)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DT.logoRed)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, DT.Space.xs)
        .background(DB.panel.opacity(0.5))
    }
}
