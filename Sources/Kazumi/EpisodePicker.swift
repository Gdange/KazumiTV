import SwiftUI

/// 播放页的剧集选择面板（对齐官方 EpisodeSelectionPanel）
struct EpisodePicker: View {
    let chapters: [Chapter]
    let current: Int
    /// Bangumi 官方剧集（用来显示正式标题）
    var bgmEpisodes: [BangumiEpisode] = []
    let onPick: (Chapter) -> Void

    /// 第 idx 集（从 0 开始）对应的官方标题
    private func officialTitle(_ idx: Int) -> String? {
        guard idx < bgmEpisodes.count else { return nil }
        let e = bgmEpisodes[idx]
        let t = e.display
        return t.isEmpty ? nil : t
    }
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("选集").font(.system(size: 26, weight: .bold))
                Text("\(chapters.count) 集").font(.system(size: 14)).foregroundStyle(KZ.dim)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).padding(8)
                }.buttonStyle(.plain)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, ch in
                        EpisodeCell(
                            name: ch.name,
                            subtitle: officialTitle(idx),
                            active: idx == current
                        ) { onPick(ch) }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(40)
        .frame(width: 1000, height: 720)
        .background(KZ.bg)
    }
}

struct EpisodeCell: View {
    let name: String
    var subtitle: String? = nil
    let active: Bool
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 15, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                if let s = subtitle {
                    Text(s)
                        .font(.system(size: 11))
                        .foregroundStyle(active ? KZ.onAccent.opacity(0.8) : KZ.dim)
                        .lineLimit(1)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(active ? KZ.onAccent : KZ.label)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(active ? KZ.accent : (focused ? KZ.accent.opacity(0.16) : KZ.card))
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
