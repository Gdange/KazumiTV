import SwiftUI

/// Kazumi 首页：搜索 + 结果网格
struct HomeView: View {
    @State private var keyword = ""
    @State private var results: [MediaItem] = []
    @State private var status = "输入关键词搜索，或直接回车看默认结果"
    @State private var loading = false
    @State private var selected: MediaItem?
    @State private var didAutoRun = false
    @FocusState private var focus: Field?

    enum Field { case search, grid }

    private let rules: [KazumiRule]
    private var source: XPathSource
    private let columns = Array(repeating: GridItem(.flexible(), spacing: KZ.cardSpace), count: KZ.columns)

    @State private var currentRule: KazumiRule

    init(rules: [KazumiRule], initial: KazumiRule) {
        self.rules = rules
        self._currentRule = State(initialValue: initial)
        self.source = XPathSource(rule: initial)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 32) {
                header
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KZ.bg.ignoresSafeArea())
            .task {
                if results.isEmpty && !didAutoRun {
                    didAutoRun = true
                    keyword = "进击"
                    await runSearch()
                }
            }
            .navigationDestination(item: $selected) { item in
                DetailView(item: item)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text("Kazumi TV")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(KZ.label)
                Text(source.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(KZ.accent)
                    .padding(.horizontal, 14).padding(.vertical, 5)
                    .background(KZ.accent.opacity(0.15))
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                TextField("搜索番剧…", text: $keyword)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(KZ.card)
                    .clipShape(Capsule())
                    .frame(maxWidth: 640)
                    .focused($focus, equals: .search)
                    .onSubmit { Task { await runSearch() } }

                Button {
                    Task { await runSearch() }
                } label: {
                    Text(loading ? "搜索中…" : "搜索")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(KZ.onAccent)
                        .padding(.horizontal, 34).padding(.vertical, 14)
                        .background(KZ.accent)
                        .clipShape(Capsule())
                }
                .disabled(loading || keyword.isEmpty)
            }

            HStack(spacing: 12) {
                Text("试试：").font(.system(size: 14)).foregroundStyle(.tertiary)
                ForEach(["进击", "海贼", "咒术", "鬼灭"], id: \.self) { w in
                    Button {
                        keyword = w
                        Task { await runSearch() }
                    } label: {
                        Text(w)
                            .font(.system(size: 15))
                            .foregroundStyle(KZ.accent)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(KZ.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(rules, id: \.name) { r in
                        Button {
                            currentRule = r
                        } label: {
                            Text(r.name)
                                .font(.system(size: 15, weight: r.name == currentRule.name ? .semibold : .regular))
                                .foregroundStyle(r.name == currentRule.name ? KZ.onAccent : KZ.label)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(
                                    Capsule().fill(r.name == currentRule.name
                                                   ? KZ.accent
                                                   : KZ.card)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(status)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if results.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(results) { item in
                        CardView(item: item) { selected = item }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text(loading ? "正在解析站点…" : "还没有结果")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func runSearch() async {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        loading = true
        status = "正在用规则 \(source.name) 搜索「\(kw)」…"
        defer { loading = false }
        do {
            let items = try await source.search(kw)
            results = items
            status = "找到 \(items.count) 条结果"
        } catch {
            results = []
            status = "搜索失败：\(error.localizedDescription)"
        }
    }
}

struct CardView: View {
    let item: MediaItem
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(KZ.card)
                    if let ps = item.poster, let u = URL(string: ps) {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill()
                            case .failure:
                                Text(item.name.prefix(1))
                                    .font(.system(size: 64, weight: .thin))
                                    .foregroundStyle(.tertiary)
                            default:
                                ProgressView()
                            }
                        }
                    } else {
                        Text(item.name.prefix(1))
                            .font(.system(size: 64, weight: .thin))
                            .foregroundStyle(.tertiary)
                    }
                }
                .aspectRatio(1/KZ.posterRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: KZ.imgRadius))
                Text(item.name)
                    .font(.system(size: 18))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .focusCard(focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
