import SwiftUI

/// 倍速面板（对齐官方 0.25x–2.0x）
struct SpeedSheet: View {
    @Binding var rate: Float
    let onPick: (Float) -> Void
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("播放速度").font(.system(size: 24, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).padding(8)
                }.buttonStyle(.plain)
            }

            VStack(spacing: 4) {
                ForEach(speeds, id: \.self) { s in
                    SpeedRow(
                        value: s,
                        active: abs(rate - s) < 0.001
                    ) { onPick(s) }
                }
            }
        }
        .padding(36)
        .frame(width: 520, height: 620)
        .background(KZ.bg)
    }
}

private struct SpeedRow: View {
    let value: Float
    let active: Bool
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(value == 1.0 ? "1.0x（正常）" : String(format: "%.2gx", value))
                    .font(.system(size: 16, weight: active ? .semibold : .regular))
                Spacer()
                if active { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)) }
            }
            .foregroundStyle(active ? KZ.accent : KZ.label)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(focused ? KZ.accent.opacity(0.16) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}

/// 定时关闭面板
struct SleepTimerSheet: View {
    let current: Int?
    let onPick: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let options: [Int] = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("定时关闭").font(.system(size: 24, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).padding(8)
                }.buttonStyle(.plain)
            }

            Text("到点自动暂停播放").font(.system(size: 13)).foregroundStyle(KZ.dim)

            VStack(spacing: 4) {
                ForEach(options, id: \.self) { m in
                    TimerRow(label: "\(m) 分钟", active: current == m) { onPick(m) }
                }
                TimerRow(label: "关闭定时", active: current == nil) { onPick(nil) }
            }
        }
        .padding(36)
        .frame(width: 520, height: 600)
        .background(KZ.bg)
    }
}

private struct TimerRow: View {
    let label: String
    let active: Bool
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label).font(.system(size: 16, weight: active ? .semibold : .regular))
                Spacer()
                if active { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)) }
            }
            .foregroundStyle(active ? KZ.accent : KZ.label)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(focused ? KZ.accent.opacity(0.16) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
