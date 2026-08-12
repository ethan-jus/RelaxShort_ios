import SwiftUI

private enum PlayerSheetStyle {
    static let background = Color(hex: "#111111")
    static let card = Color.white.opacity(0.065)
    static let divider = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.55)
    static let cornerRadius: CGFloat = 24
}

struct PlayerQualitySheet: View {
    struct QualityOption: Identifiable {
        let id: String
        let label: String
        let detail: String?
        let isVIP: Bool
        let isAvailable: Bool
        let isSelected: Bool
    }

    @Environment(\.dismiss) private var dismiss

    let selectedRate: Float
    let qualities: [QualityOption]
    let subtitles: [PlayerSubtitleOption]
    let selectedSubtitleID: String?
    let onSelectRate: (Float) -> Void
    let onSelectQuality: (String) -> Void
    let onSelectSubtitle: (String?) -> Void

    private let speeds: [(String, Float)] = [
        ("0.75x", 0.75), ("1.0x", 1.0), ("1.25x", 1.25),
        ("1.5x", 1.5), ("2.0x", 2.0), ("3.0x", 3.0)
    ]

    init(
        selectedRate: Float,
        qualities: [QualityOption],
        subtitles: [PlayerSubtitleOption],
        selectedSubtitleID: String?,
        onSelectRate: @escaping (Float) -> Void,
        onSelectQuality: @escaping (String) -> Void,
        onSelectSubtitle: @escaping (String?) -> Void
    ) {
        self.selectedRate = selectedRate
        self.qualities = qualities
        self.subtitles = subtitles
        self.selectedSubtitleID = selectedSubtitleID
        self.onSelectRate = onSelectRate
        self.onSelectQuality = onSelectQuality
        self.onSelectSubtitle = onSelectSubtitle
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            HStack {
                Text("player.playback_settings".localized)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.66))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.055), in: Circle())
                }
                .accessibilityLabel("general.close".localized)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 7)

                speedSection
                    .padding(.horizontal, 20)

                sectionTitle(L10n.quality)
                    .padding(.top, 26)
                    .padding(.horizontal, 20)

                qualitySection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                sectionTitle("player.subtitles".localized)
                    .padding(.top, 26)
                    .padding(.horizontal, 20)

                subtitleSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.hidden)
        .background(PlayerSheetStyle.background)
        .presentationBackground(PlayerSheetStyle.background)
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("player.speed".localized)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
            ForEach(speeds, id: \.0) { label, value in
                let selected = abs(selectedRate - value) < 0.01
                Button {
                    onSelectRate(value)
                } label: {
                    Text(label)
                        .font(.system(size: 15, weight: selected ? .bold : .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(selected ? DT.logoRed : PlayerSheetStyle.card)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(.white.opacity(selected ? 0.16 : 0.07), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
            }
        }
    }

    private var qualitySection: some View {
        VStack(spacing: 0) {
            ForEach(qualities) { option in
                Button {
                    onSelectQuality(option.id)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(option.label)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                if option.isVIP {
                                    Text("VIP")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(Color.black.opacity(0.86))
                                        .padding(.horizontal, 6)
                                        .frame(height: 17)
                                        .background(DT.memberGold, in: Capsule())
                                }
                            }
                            if let detail = option.detail {
                                Text(detail)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(PlayerSheetStyle.secondary)
                            }
                        }
                        Spacer()
                        if option.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 23, height: 23)
                                .background(DT.logoRed, in: Circle())
                        } else if !option.isAvailable {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: option.detail == nil ? 52 : 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if option.id != qualities.last?.id {
                    Rectangle().fill(PlayerSheetStyle.divider).frame(height: 1)
                }
            }
        }
        .background(PlayerSheetStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subtitleSection: some View {
        VStack(spacing: 0) {
            subtitleRow(id: nil, title: "player.subtitles_off".localized)
            ForEach(subtitles) { option in
                Rectangle().fill(PlayerSheetStyle.divider).frame(height: 1)
                subtitleRow(id: option.id, title: option.displayName)
            }
        }
        .background(PlayerSheetStyle.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func subtitleRow(id: String?, title: String) -> some View {
        Button {
            onSelectSubtitle(id)
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                if selectedSubtitleID == id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DT.logoRed)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    PlayerQualitySheet(
        selectedRate: 1,
        qualities: [
            .init(id: "auto", label: "Auto", detail: "player.quality_auto_standard".localized,
                  isVIP: false, isAvailable: true, isSelected: true),
            .init(id: "720p", label: "720P", detail: nil,
                  isVIP: false, isAvailable: true, isSelected: false),
            .init(id: "1080p", label: "1080P", detail: nil,
                  isVIP: true, isAvailable: false, isSelected: false)
        ],
        subtitles: [],
        selectedSubtitleID: nil,
        onSelectRate: { _ in },
        onSelectQuality: { _ in },
        onSelectSubtitle: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
