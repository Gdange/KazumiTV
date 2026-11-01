import SwiftUI

/// 播放来源面板（对齐官方「播放来源」弹窗）
/// 列出所有源及其状态：N 个结果 / 需要验证 / 检索失败
struct SourcePanel: View {
    @ObservedObject var matcher: SourceMatcher
    let onPick: (SourceMatcher.Entry, MediaItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.horizontal, 40)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(matcher.entries) { entry in
                        SourceRow(
                            entry: entry,
                            expanded: expanded.contains(entry.id),
                            onToggle: {
                                if expanded.contains(entry.id) { expanded.remove(entry.id) }
                                else { expanded.insert(entry.id) }
                            },
                            onPick: { item in
                                onPick(entry, item)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 900, height: 760)
        .background(KZ.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("播放来源").font(.system(size: 26, weight: .bold))
                Text("\(matcher.entries.count) 个来源 · \(matcher.totalResults) 个结果")
                    .font(.system(size: 14)).foregroundStyle(KZ.dim)
            }
            Spacer()
            if !matcher.finished {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("扫描中 \(matcher.usableCount)").font(.system(size: 13)).foregroundStyle(KZ.dim)
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold))
                    .padding(10)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 40).padding(.top, 30).padding(.bottom, 16)
    }
}

/// 一行 = 一个来源
struct SourceRow: View {
    let entry: SourceMatcher.Entry
    let expanded: Bool
    let onToggle: () -> Void
    let onPick: (MediaItem) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Text(entry.id).font(.system(size: 16, weight: .medium))
                    Spacer()
                    statusLabel
                    if entry.count > 0 {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KZ.dim)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(focused ? KZ.accent.opacity(0.15) : KZ.card.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .focused($focused)
            .disabled(entry.count == 0 || entry.playable != .yes)

            // 展开：这个源的所有结果
            if expanded, case .results(let items) = entry.state {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        ResultRow(item: item) { onPick(item) }
                    }
                }
                .padding(.leading, 18).padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch entry.state {
        case .pending:
            Text("检索中…").font(.system(size: 13)).foregroundStyle(KZ.dim)
        case .results(let r):
            HStack(spacing: 8) {
                Text("\(r.count) 个结果")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KZ.accent)
                switch entry.playable {
                case .checking:
                    Text("检测中…").font(.system(size: 12)).foregroundStyle(KZ.dim)
                case .yes:
                    Text("可播放")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(KZ.accent)
                        .foregroundStyle(KZ.bg)
                        .clipShape(Capsule())
                case .no(let why):
                    Text(why)
                        .font(.system(size: 11))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
        case .needsVerify:
            Text("需要验证").font(.system(size: 13)).foregroundStyle(.orange)
        case .failed(let why):
            Text(why).font(.system(size: 13)).foregroundStyle(KZ.dim)
        }
    }
}

/// 单个结果条目
struct ResultRow: View {
    let item: MediaItem
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 11))
                Text(item.name).font(.system(size: 14)).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(focused ? KZ.accent.opacity(0.2) : .clear)
            )
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
