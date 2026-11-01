import SwiftUI

/// 推荐：热门番组（对齐官方 PopularPage）
/// —— 官方首页是「内容发现」，搜索是独立入口，不是默认搜索
struct PopularView: View {
    @State private var items: [BangumiItem] = []
    @State private var status = "正在加载热门番组…"
    @State private var loading = false
    @State private var showSearch = false
    @State private var offset = 0
    @State private var tag = ""            // "" = 热门番组
    @State private var opened: MediaItem?
    @State private var openingID: Int?
    @State private var openError: String?

    private let pageSize = 24
    private let columns = Array(repeating: GridItem(.flexible(), spacing: KZ.cardSpace), count: KZ.columns)

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(item: $opened) { m in
                    DetailView(item: m, initialRule: defaultRule)
                }
        }
    }

    private var defaultRule: KazumiRule {
        RuleCatalog.installed().first?.rule ?? RulesStore.loadBundled().first!
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            topBar
            tagBar.focusSection()
            Text(status).font(.system(size: 13)).foregroundStyle(KZ.dim)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 26) {
                    ForEach(items) { item in
                        PosterCard(name: item.displayName, image: item.image) {
                            Task { await open(item) }
                        }
                        .onAppear {
                            if item.id == items.last?.id { Task { await loadMore() } }
                        }
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .padding(.horizontal, 60).padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KZ.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showSearch) {
            SearchView()
        }
        .task { if items.isEmpty { await loadMore() } }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(tag.isEmpty ? "热门番组" : tag)
                .font(.system(size: 40, weight: .bold))

            Spacer()

            Button { showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16))
                    Text("搜索").font(.system(size: 15))
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(KZ.card))
            }
            .buttonStyle(.plain)
        }
    }

    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                tagChip("热门番组", value: "")
                ForEach(AnimeTags.all, id: \.self) { t in
                    tagChip(t, value: t)
                }
            }
        }
    }

    private func tagChip(_ label: String, value: String) -> some View {
        Button {
            guard tag != value else { return }
            tag = value
            items = []
            offset = 0
            Task { await loadMore() }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: tag == value ? .semibold : .regular))
                .foregroundStyle(tag == value ? KZ.onAccent : KZ.label)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(tag == value ? KZ.accent : KZ.card))
        }
        .buttonStyle(.plain)
    }

    /// 点海报：按条目名在当前源里搜一次，取最近匹配进详情
    private func open(_ item: BangumiItem) async {
        guard openingID == nil else { return }
        openingID = item.id
        defer { openingID = nil }

        let name = item.displayName
        let src = XPathSource(rule: defaultRule)
        do {
            let results = try await src.search(name)
            guard let first = results.first else {
                status = "「\(name)」在该源没搜到"
                return
            }
            opened = first
        } catch {
            status = "打开失败：\(error.localizedDescription)"
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let batch = tag.isEmpty
                ? try await BangumiAPI.trending(limit: pageSize, offset: offset)
                : try await BangumiAPI.byTag(tag)
            if batch.isEmpty {
                status = "共 \(items.count) 部"
                return
            }
            offset += pageSize
            let existing = Set(items.map(\.id))
            items.append(contentsOf: batch.filter { !existing.contains($0.id) })
            status = "共 \(items.count) 部"
        } catch {
            status = "加载失败：\(error.localizedDescription)"
        }
    }
}
