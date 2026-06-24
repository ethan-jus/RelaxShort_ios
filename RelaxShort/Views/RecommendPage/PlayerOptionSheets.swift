import SwiftUI

// MARK: - Player Speed Sheet

/// 倍速选择底部面板
struct PlayerSpeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedRate: Float
    let onSelect: (Float) -> Void

    private let speeds: [(label: String, value: Float)] = [
        ("3.0x", 3.0), ("2.0x", 2.0), ("1.5x", 1.5),
        ("1.25x", 1.25), ("1.0x", 1.0), ("0.75x", 0.75)
    ]

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
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(speeds, id: \.label) { speed in
                    let isSelected = abs(selectedRate - speed.value) < 0.01
                    Button {
                        onSelect(speed.value)
                        dismiss()
                    } label: {
                        Text(speed.label)
                            .font(.system(size: 16, weight: isSelected ? .bold : .semibold))
                            .foregroundColor(isSelected ? .white : .white.opacity(0.78))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? DB.pink.opacity(0.95) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .background(DB.panelElevated)
    }
}

// MARK: - Player Quality Sheet

/// 清晰度选择底部面板
struct PlayerQualitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let qualities: [QualityOption]
    let currentQuality: String
    let onSelect: (String) -> Void

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
                    Button {
                        onSelect(option.id)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Text(option.label)
                                .font(.system(size: 16, weight: option.isVIP ? .bold : .medium))
                                .foregroundColor(option.isVIP ? DB.gold : .white)
                            if option.isVIP {
                                ZStack {
                                    Image(systemName: "hexagon.fill")
                                        .font(.system(size: 21, weight: .bold))
                                    Text("V")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundColor(.black.opacity(0.86))
                                }
                                .foregroundColor(DB.gold)
                            }
                            Spacer()
                            if option.isSelected {
                                Circle()
                                    .fill(option.isVIP ? DB.gold : DB.pink)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(option.isVIP ? .black : .white)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(option.isSelected ? Color.white.opacity(0.12) : Color.clear)
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

// MARK: - Player More Sheet

/// 更多选项底部面板（清晰度/字幕/反馈）
struct PlayerMoreSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSpeed: () -> Void
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
                moreRow(icon: "timer", title: "Speed", disabled: false) {
                    dismiss(); onSpeed()
                }
                Divider().background(Color.white.opacity(0.08)).padding(.leading, 56)

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
        PlayerSpeedSheet(selectedRate: 1.0, onSelect: { _ in })
            .preferredColorScheme(.dark)
    }
}
#endif
