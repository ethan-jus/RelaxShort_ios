import SwiftUI

// MARK: - Profile Identity Header

/// 顶部用户信息区。已登录显示真实头像/昵称/ID/Following/VIP；
/// 未登录显示默认头像和登录入口。
struct ProfileIdentityHeader: View {
    let avatarURL: String?
    let title: String
    let subtitle: String
    let followingText: String?
    let isVIP: Bool
    let onTap: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DT.Space.md) {
            // 头像
            Button(action: onTap) {
                ProfileAvatarView(url: avatarURL, initials: String(title.prefix(2)).uppercased(), size: 76)
            }

            // 昵称 / ID / Following
            VStack(alignment: .leading, spacing: DT.Space.xs) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DT.Font.caption)
                    .foregroundColor(DT.Color.textSecondary)

                if let following = followingText {
                    HStack(spacing: DT.Space.xs) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DT.Color.textSecondary)
                        Text(following)
                            .font(.system(size: 12))
                            .foregroundColor(DT.Color.textSecondary)
                    }
                }

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
                    .background(DB.gold.opacity(0.15))
                    .cornerRadius(DT.Radius.sm)
                }
            }

            Spacer()

            // 设置按钮
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(DT.Color.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, DT.Space.md)
    }
}

// MARK: - Profile Avatar

struct ProfileAvatarView: View {
    let url: String?
    let initials: String
    let size: CGFloat

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
                        .fill(DB.panelElevated)
                        .frame(width: size, height: size)
                    Text(initials)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundColor(DT.Color.textSecondary)
                }
            }
        }
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
                        Text("profile.sign_in_subtitle".localized)
                            .font(DT.Font.small)
                            .foregroundColor(DT.Color.textSecondary)
                    }
                    Spacer()
                    Button(action: onJoin) {
                        Text("profile.join_membership".localized)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, DT.Space.md)
                            .padding(.vertical, DT.Space.xs)
                            .background(DT.logoRed)
                            .cornerRadius(DT.Radius.sm)
                    }
                }
                .padding(DT.Space.lg)

                // 4 项核心权益
                HStack(spacing: 0) {
                    membershipBenefit(icon: "play.rectangle.fill", text: "profile.membership_benefit_series".localized)
                    membershipBenefit(icon: "star.fill", text: "profile.membership_benefit_points".localized)
                    membershipBenefit(icon: "arrow.down.to.line", text: "profile.membership_benefit_download".localized)
                    membershipBenefit(icon: "4k.tv", text: "profile.membership_benefit_quality".localized)
                }
                .padding(.bottom, DT.Space.md)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "#3D1111"), Color(hex: "#1A0A0A"), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: DB.cardRadius))
        .padding(.horizontal, DT.Space.pageH)
        .padding(.top, DT.Space.sm)
    }

    private func membershipBenefit(icon: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.9))
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(DT.Color.textSecondary)
                .lineLimit(1)
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
    let onTap: () -> Void

    init(icon: String, iconColor: Color = .white, title: String, subtitle: String? = nil, onTap: @escaping () -> Void) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
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
            .frame(minHeight: 56)
        }
        .buttonStyle(.plain)

        if title != "profile.help_feedback".localized {
            Divider()
                .background(DB.divider)
                .padding(.leading, 56)
        }
    }
}

// MARK: - Skeleton & Error States

struct ProfileHeaderSkeleton: View {
    var body: some View {
        HStack(spacing: DT.Space.md) {
            Circle()
                .fill(DB.panelElevated)
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(DB.panelElevated)
                    .frame(width: 120, height: 16)
                RoundedRectangle(cornerRadius: 4)
                    .fill(DB.panelElevated)
                    .frame(width: 80, height: 12)
            }
            Spacer()
        }
        .padding(.horizontal, DT.Space.pageH)
        .padding(.vertical, DT.Space.md)
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
