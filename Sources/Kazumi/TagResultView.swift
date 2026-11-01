import SwiftUI

/// 标签结果页：点详情页的标签 → 按该标签列出番剧
struct TagResultView: View {
    let tag: String
    @Environment(\.dismiss) private var dismiss

    @State private var items: [BgmSearchItem] = []
    @State private var status = "正在按标签搜索…"
    @State private var loading = false
    @State private var sort = "heat"
    @StateObject private var route = DetailRoute.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: KZ.cardSpace), count: KZ.columns)

    private var tagName: String {
        var t = tag
        if t.hasPrefix("tag:") { t = String(t.dropFirst(4)) }
        // 去掉尾部的数量（如「恋爱 172」）
        if let sp = t.lastIndex(of: " "), Int(t[t.index(after: sp)...]) != nil {
            t = String(t[..<sp])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                sortBar
                Text(status).font(.system(size: 13)).foregroundStyle(KZ.dim)
                content
            }
            .padding(.horizontal, 60).padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KZ.bg.ignoresSafeArea())
            .navigationDestination(item: $route.opened) { m in
                DetailView(item: m, initialRule: defaultRule)
            }
        }
        .task { await load() }
    }

    private var defaultRule: KazumiRule {
        RuleCatalog.installed().first?.rule ?? RulesStore.loadBundled().first!
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44).background(Circle().fill(KZ.card))
            }
            .buttonStyle(.plain)

            Text(tagName).font(.system(size: 34, weight: .bold))
            Spacer()
        }
    }

    private var sortBar: some View {
        HStack(spacing: 10) {
            ForEach([("heat", "热度"), ("rank", "排名"), ("score", "评分"), ("match", "匹配")], id: \.0) { key, label in
                Button {
                    guard sort != key else { return }
                    sort = key
                    Task { await load() }
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: sort == key ? .semibold : .regular))
                        .foregroundStyle(sort == key ? KZ.onAccent : KZ.label)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(sort == key ? KZ.accent : KZ.card))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 12) {
                if loading { ProgressView() }
                Text(loading ? "搜索中…" : status).font(.system(size: 17)).foregroundStyle(KZ.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(items) { item in
                        Button {
                            Task { await route.open(name: item.displayName) }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: KZ.imgRadius).fill(KZ.card)
                                    if let s = item.image, let u = URL(string: s) {
                                        AsyncImage(url: u) { phase in
                                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                                            else { Text(item.displayName.prefix(1))
                                                    .font(.system(size: 48, weight: .thin)).foregroundStyle(KZ.dim) }
                                        }
                                    } else {
                                        Text(item.displayName.prefix(1))
                                            .font(.system(size: 48, weight: .thin)).foregroundStyle(KZ.dim)
                                    }
                                }
                                .aspectRatio(1/KZ.posterRatio, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: KZ.imgRadius))

                                Text(item.displayName).font(.system(size: 16)).lineLimit(2)
                                    .foregroundStyle(KZ.label)
                                HStack(spacing: 8) {
                                    if let sc = item.score, sc > 0 {
                                        HStack(spacing: 3) {
                                            Image(systemName: "star.fill").font(.system(size: 10))
                                            Text(String(format: "%.1f", sc)).font(.system(size: 12))
                                        }.foregroundStyle(KZ.accent)
                                    }
                                    if !item.year.isEmpty {
                                        Text(item.year).font(.system(size: 12)).foregroundStyle(KZ.dim)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var q = SearchQuery()
        q.tags = [tagName]
        q.sort = sort
        do {
            items = try await BangumiAPI.search(q)
            status = "共 \(items.count) 部（标签「\(tagName)」· 原始「\(tag)」· 排序 \(sort)）"
        } catch {
            items = []
            status = "搜索失败：\(error.localizedDescription)（标签「\(tagName)」）"
        }
    }
}
