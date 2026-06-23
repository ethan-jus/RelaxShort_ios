import SwiftUI

// MARK: - Player Speed Sheet

/// Task26: 倍速选择底部面板
struct PlayerSpeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let engine: ShortVideoPlayerEngine

    private let speeds: [(label: String, value: Float)] = [
        ("3.0x", 3.0), ("2.0x", 2.0), ("1.5x", 1.5),
        ("1.25x", 1.25), ("1.0x", 1.0), ("0.75x", 0.75)
    ]

    @State private var selected: Float = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer().frame(width: 36)
                Spacer()
                Text("Speed")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach(speeds, id: \.label) { speed in
                    Button {
                        selected = speed.value
                        engine.setRate(speed.value)
                        dismiss()
                    } label: {
                        HStack {
                            Text(speed.label)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            if abs(selected - speed.value) < 0.01 {
                                Circle()
                                    .fill(DB.pink)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(abs(selected - speed.value) < 0.01 ? Color.white.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 34)
        }
        .background(DB.panelElevated)
    }
}

// MARK: - Player Quality Sheet

/// Task26: 清晰度选择底部面板
struct PlayerQualitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let qualities: [QualityOption]
    let currentQuality: String

    struct QualityOption: Identifiable {
        let id: String
        let label: String
        let isVIP: Bool
        let isSelected: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer().frame(width: 36)
                Spacer()
                Text("Current Quality")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach(qualities) { option in
                    HStack {
                        Text(option.label)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(option.isVIP ? .white.opacity(0.35) : .white)
                        if option.isVIP {
                            Text("VIP")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(DB.gold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DB.gold.opacity(0.15)))
                        }
                        Spacer()
                        if option.isSelected {
                            Circle()
                                .fill(DB.pink)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(option.isSelected ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .disabled(option.isVIP)
                }
            }
            .padding(.bottom, 34)
        }
        .background(DB.panelElevated)
    }
}

// MARK: - Player More Sheet

/// Task26: 更多选项底部面板（清晰度/字幕/反馈）
struct PlayerMoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onQuality: () -> Void
    var onSubtitles: () -> Void
    var onReport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                moreRow(icon: "4k.tv", title: "Quality", disabled: false) {
                    dismiss(); onQuality()
                }
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 56)

                moreRow(icon: "captions.bubble", title: "Subtitles", disabled: true) {
                    dismiss(); onSubtitles()
                }
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 56)

                moreRow(icon: "exclamationmark.bubble", title: "Report subtitle issue", disabled: true) {
                    dismiss(); onReport()
                }
            }

            Spacer().frame(height: 34)
        }
        .background(DB.panelElevated)
    }

    private func moreRow(icon: String, title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(disabled ? .white.opacity(0.25) : .white.opacity(0.8))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(disabled ? .white.opacity(0.25) : .white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#if DEBUG
struct PlayerSpeedSheet_Previews: PreviewProvider {
    static var previews: some View {
        PlayerSpeedSheet(engine: PlayerCoordinator().engine)
            .preferredColorScheme(.dark)
    }
}
#endif
