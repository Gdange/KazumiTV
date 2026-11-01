import SwiftUI

/// 搜索：Bangumi 番剧搜索 + 采集源搜索（对齐官方 SearchPage）
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var keyword = ""
    @State private var mode: Mode = .bangumi
    @State private var bgmResults: [BgmSearchItem] = []
    @State private var srcResults: [MediaItem] = []
    @State private var status = "输入关键词，支持 tag: / sort: / score: 语法"
    @State private var loading = false
    @State private var opened: MediaItem?
    @StateObject private var history = SearchHistoryStore.shared
    @StateObject private var route = DetailRoute()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: KZ.cardSpace), count: KZ.columns)

    enum Mode: String, CaseIterable, Identifiable {
        case bangumi = "番剧搜索"
        case source = "片源搜索"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            inner
                .navigationDestination(item: $route.opened) { m in
                    DetailView(item: m, initialRule: defaultRule)
                }
        }
    }

    private var defaultRule: KazumiRule {
        RuleCatalog.installed().first?.rule ?? RulesStore.loadBundled().first!
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 16) {
            searchBar
            modeBar.focusSection()
            Text(status).font(.system(size: 13)).foregroundStyle(KZ.dim)
            content
        }
        .padding(.horizontal, 60).padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KZ.bg.ignoresSafeArea())
    }

    private var searchBar: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44).background(Circle().fill(KZ.card))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(KZ.dim)
                TextField("番剧名 或 tag:卖肉 sort:heat", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .onSubmit { Task { await run() } }
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(KZ.dim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(Capsule().fill(KZ.card))
            .frame(maxWidth: 560)

            Button { Task { await run() } } label: {
                Text(loading ? "搜索中…" : "搜索")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KZ.onAccent)
                    .padding(.horizontal, 26).padding(.vertical, 11)
                    .background(Capsule().fill(KZ.accent))
            }
            .buttonStyle(.plain)
            .disabled(loading)
            Spacer()
        }
    }

    private var modeBar: some View {
        HStack(spacing: 10) {
            ForEach(Mode.allCases) { m in
                Button { mode = m } label: {
                    Text(m.rawValue)
                        .font(.system(size: 14, weight: mode == m ? .semibold : .regular))
                        .foregroundStyle(mode == m ? KZ.onAccent : KZ.label)
                        .padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(mode == m ? KZ.accent : KZ.card))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .bangumi:
            if bgmResults.isEmpty { emptyState } else { bgmGrid }
        case .source:
            if srcResults.isEmpty { emptyState } else { srcGrid }
        }
    }

    private var bgmGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(bgmResults) { item in
                    Button {
                        Task { await route.open(name: item.displayName) }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            posterBox(item.image, item.displayName)
                            Text(item.displayName).font(.system(size: 16)).lineLimit(2)
                                .foregroundStyle(KZ.label)
                            HStack(spacing: 8) {
                                if let s = item.score, s > 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: "star.fill").font(.system(size: 10))
                                        Text(String(format: "%.1f", s)).font(.system(size: 12))
                                    }
                                    .foregroundStyle(KZ.accent)
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

    private var srcGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(srcResults) { item in
                    Button {
                        opened = item
                        route.opened = item
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            posterBox(item.poster, item.name)
                            Text(item.name).font(.system(size: 16)).lineLimit(2)
                                .foregroundStyle(KZ.label)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 50)
        }
    }

    private func posterBox(_ url: String?, _ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: KZ.imgRadius).fill(KZ.card)
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Text(name.prefix(1)).font(.system(size: 48, weight: .thin)).foregroundStyle(KZ.dim) }
                }
            } else {
                Text(name.prefix(1)).font(.system(size: 48, weight: .thin)).foregroundStyle(KZ.dim)
            }
        }
        .aspectRatio(1/KZ.posterRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: KZ.imgRadius))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: loading ? "hourglass" : "magnifyingglass")
                .font(.system(size: 50, weight: .thin)).foregroundStyle(KZ.dim)
            Text(loading ? "搜索中…" : "输入关键词开始搜索").font(.system(size: 17)).foregroundStyle(KZ.dim)
            if !history.keywords.isEmpty && !loading {
                HStack(spacing: 8) {
                    ForEach(history.keywords.prefix(5), id: \.self) { kw in
                        Button { keyword = kw; Task { await run() } } label: {
                            Text(kw).font(.system(size: 13))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(KZ.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 340)
    }

    private func run() async {
        let raw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        loading = true
        defer { loading = false }
        history.add(raw)

        switch mode {
        case .bangumi:
            status = "正在搜索 Bangumi…"
            do {
                let q = SearchParser.parse(raw)
                var parts: [String] = []
                if !q.tags.isEmpty { parts.append("标签 \(q.tags.joined(separator: ","))") }
                if q.sort != "match" { parts.append("排序 \(q.sort)") }
                if let (a, b) = q.scoreRange { parts.append("评分 \(a)~\(b)") }
                bgmResults = try await BangumiAPI.search(q)
                status = "找到 \(bgmResults.count) 部番剧" + (parts.isEmpty ? "" : "（\(parts.joined(separator: " · "))）")
            } catch {
                bgmResults = []
                status = "搜索失败：\(error.localizedDescription)"
            }
        case .source:
            status = "正在用「\(defaultRule.name)」搜索…"
            do {
                srcResults = try await XPathSource(rule: defaultRule).search(raw)
                status = "找到 \(srcResults.count) 条片源"
            } catch {
                srcResults = []
                status = "搜索失败：\(error.localizedDescription)"
            }
        }
    }
}
