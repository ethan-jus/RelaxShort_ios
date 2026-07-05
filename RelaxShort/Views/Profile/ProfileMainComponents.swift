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
        VStack(spacing: DT.Space.xs) {
            HStack {
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("profile.settings".localized)
            }
            .frame(height: 44)

            HStack(alignment: .center, spacing: DT.Space.md) {
                Button(action: onTap) {
                    ProfileAvatarView(
                        url: avatarURL,
                        initials: String(title.prefix(2)).uppercased(),
                        size: 72,
                        showsGuestIcon: isGuest
                    )
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: DT.Space.sm) {
                    Button(action: onTap) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 21, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            if isGuest {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: DT.Space.sm) {
                        HStack(spacing: 5) {
                            Text("ID \(displayID)")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            CopyIDButton(displayID: displayID)
                        }

                        Rectangle()
                            .fill(DB.divider)
                            .frame(width: 1, height: 13)

                        HStack(spacing: 5) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(L10n.favoriteCount(favoriteCount))
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DT.Color.textSecondary)

                    if isVIP {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10))
                            Text("VIP")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(DB.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(DB.gold.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.bottom, DT.Space.md)
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
                .foregroundColor(didCopy ? DB.gold : .white.opacity(0.72))
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
                                colors: [Color(hex: "#35363A"), Color(hex: "#222327")],
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

/// 会员卡：深红到黑色渐变，主按钮使用 Logo 红。
/// 非会员显示"加入会员"、4 项核心权益和加入按钮。
/// 已开通会员显示会员状态与真实有效期。
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

    var body: some View {
        VStack(spacing: 0) {
            if isVIP {
                // 已开通会员
                HStack {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 18))
                        .foregroundColor(DB.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("profile.membership_active".localized)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text(expiryText)
                            .font(DT.Font.caption)
                            .foregroundColor(DT.Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(DT.Space.lg)
            } else {
                // 非会员：加入会员
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("profile.join_membership".localized)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text("vip.unlock_all".localized)
                            .font(DT.Font.small)
                            .foregroundColor(DT.Color.textSecondary)
                    }
                    Spacer()
                    Text("profile.join_membership".localized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, DT.Space.md)
                        .padding(.vertical, DT.Space.xs)
                        .background(DT.logoRed)
                        .cornerRadius(DT.Radius.sm)
                }
                .padding(DT.Space.lg)

                // 4 项核心权益：黑金风格，全部金色图标
                HStack(spacing: 0) {
                    membershipBenefit(icon: "play.rectangle.fill", text: "profile.membership_benefit_series".localized)
                    membershipBenefit(icon: "gift.fill", text: "profile.membership_benefit_points".localized)
                    membershipBenefit(icon: "arrow.down.to.line", text: "profile.membership_benefit_download".localized)
                    membershipBenefit(icon: "tv.fill", text: "profile.membership_benefit_quality".localized)
                }
                .padding(.bottom, DT.Space.md)
            }
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "#1E1A14"),
                        Color(hex: "#161310"),
                        Color(hex: "#0E0D10")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [DB.gold.opacity(0.15), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 190
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DB.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DB.cardRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            DB.gold.opacity(0.55),
                            DB.gold.opacity(0.18),
                            .white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: DB.gold.opacity(0.12), radius: 14, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: DB.cardRadius))
        .onTapGesture(perform: onJoin)
        .accessibilityAddTraits(.isButton)
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
    }

    private func membershipBenefit(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(DB.gold.opacity(0.9))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(minHeight: 24, alignment: .top)
        }
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
        .background(DB.panel)
        .clipShape(RoundedRectangle(cornerRadius: DB.cardRadius))
        .padding(.horizontal, DT.Space.pageH)
    }
}

// MARK: - Profile Menu Row

struct ProfileMenuRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let showsDivider: Bool
    let onTap: () -> Void

    init(
        icon: String,
        iconColor: Color = .white,
        title: String,
        subtitle: String? = nil,
        showsDivider: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.showsDivider = showsDivider
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DT.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.white)

                Spacer()

                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundColor(DT.Color.textSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(DB.mutedText)
            }
            .padding(.horizontal, DT.Space.lg)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)

        if showsDivider {
            Divider()
                .background(DB.divider)
                .padding(.leading, 56)
        }
    }
}

// MARK: - Skeleton & Error States

struct ProfileHeaderSkeleton: View {
    var body: some View {
        VStack(spacing: DT.Space.xs) {
            HStack {
                Spacer()
                Circle()
                    .fill(DB.panelElevated)
                    .frame(width: 36, height: 36)
                    .padding(4)
            }
            .frame(height: 44)

            HStack(spacing: DT.Space.md) {
                Circle()
                    .fill(DB.panelElevated)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DB.panelElevated)
                        .frame(width: 120, height: 18)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DB.panelElevated)
                        .frame(width: 150, height: 12)
                }
                Spacer()
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.bottom, DT.Space.md)
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
