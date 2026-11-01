import SwiftUI

/// 详情页：Bangumi 条目信息 + 剧集（对齐官方 InfoPage）
struct DetailView: View {
    let item: MediaItem
    var initialRule: KazumiRule? = nil

    @State private var subject: BangumiSubject?
    @State private var chapters: [Chapter] = []
    @State private var status = "读取中…"
    @State private var loading = true
    @State private var playing: Chapter?
    @State private var target: PlaybackTarget?
    @State private var showFullSummary = false
    @State private var tagRoute: TagRoute?
    @State private var playItem: MediaItem?
    @State private var playRoute: PlayRoute?
    @State private var showStatusPicker = false
    @State private var showRating = false
    @State private var tab: InfoTab = .overview
    @State private var comments: [BgmComment] = []
    @State private var characters: [BgmCharacter] = []
    @State private var relations: [BgmRelation] = []
    @State private var staff: [BgmStaff] = []
    @State private var chapterError = false
    @StateObject private var collection = CollectionStore.shared
    @StateObject private var matcher = SourceMatcher()
    @State private var currentSource: XPathSource?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var isCollected: Bool { collection.contains(item) }
    private var currentStatus: CollectStatus? { collection.status(of: item) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBlock
                if let s = subject { infoBlock(s) }
                chapterSection
            }
            .padding(.horizontal, 60)
            .padding(.top, 40)
            .padding(.bottom, 60)
        }
        .background(KZ.bg.ignoresSafeArea())
        .fullScreenCover(item: $playRoute) { r in
            PlayScreen(target: r.target, title: r.title)
        }
        .fullScreenCover(item: $tagRoute) { r in
            TagResultView(tag: r.tag)
        }
        .task { await load() }
    }

    // MARK: 播放源切换（官方 InfoPage 顶部那排）
    private var sourceBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if matcher.scanning {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在查找可用播放源…").font(.system(size: 14)).foregroundStyle(KZ.dim)
                }
            } else if matcher.hits.isEmpty {
                Text("没有源收录这部番").font(.system(size: 14)).foregroundStyle(.orange)
            } else {
                HStack(spacing: 10) {
                    Text("播放源").font(.system(size: 14)).foregroundStyle(KZ.dim)
                    ForEach(matcher.hits) { hit in
                        Button {
                            Task { await selectSource(hit) }
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(currentSource?.name == hit.id ? KZ.onAccent : KZ.accent)
                                    .frame(width: 6, height: 6)
                                Text(hit.id).font(.system(size: 14,
                                    weight: currentSource?.name == hit.id ? .semibold : .regular))
                            }
                            .foregroundStyle(currentSource?.name == hit.id ? KZ.onAccent : KZ.label)
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(currentSource?.name == hit.id ? KZ.accent : KZ.card))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: 海报 + 核心信息
    private var topBlock: some View {
        HStack(alignment: .top, spacing: 40) {
            poster

            VStack(alignment: .leading, spacing: 18) {
                Text(subject?.displayName ?? item.name)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(KZ.label)
                    .lineLimit(2)

                VStack(alignment: .leading, spacing: 12) {
                    if let date = subject?.date, !date.isEmpty {
                        infoLine("放送开始", date, big: true)
                    }
                    if let score = subject?.score, score > 0 {
                        Button { showRating = true } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    infoLine("评分", String(format: "%.1f", score), big: true)
                                    if let total = subject?.ratingTotal, total > 0 {
                                        Text("\(total) 人评分")
                                            .font(.system(size: 13)).foregroundStyle(KZ.dim)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11)).foregroundStyle(KZ.dim)
                                }
                                stars(score)
                            }
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("评分分布", isPresented: $showRating) {
                            if let counts = subject?.scoreCounts, counts.count == 10 {
                                ForEach(Array(counts.enumerated().reversed()), id: \.offset) { i, n in
                                    Text("\(i + 1) 分 · \(n) 人")
                                }
                            }
                            Button("知道了", role: .cancel) { }
                        }
                    }
                    if let rank = subject?.rank, rank > 0 {
                        infoLine("Bangumi 排名", "#\(rank)", big: true)
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        showStatusPicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: currentStatus == nil ? "heart" : "heart.fill")
                            Text(currentStatus?.label ?? "未追")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(currentStatus == nil ? KZ.label : KZ.onAccent)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Capsule().fill(currentStatus == nil ? KZ.card : KZ.accent))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("追番状态", isPresented: $showStatusPicker) {
                        ForEach(CollectStatus.allCases) { st in
                            Button(st.label) { collection.setStatus(item, to: st) }
                        }
                        if currentStatus != nil {
                            Button("取消追番", role: .destructive) { collection.removeByItem(item) }
                        }
                    }

                    if let first = chapters.first {
                        Button { Task { await resolve(first) } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("开始观看")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KZ.onAccent)
                            .padding(.horizontal, 24).padding(.vertical, 11)
                            .background(Capsule().fill(KZ.accent))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)

                Text(status).font(.system(size: 13)).foregroundStyle(KZ.dim)
            }
            Spacer(minLength: 0)
        }
    }

    private var poster: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KZ.imgRadius).fill(KZ.card)
            let url = subject?.image ?? item.poster
            if let s = url, let u = URL(string: s) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Text(item.name.prefix(1))
                            .font(.system(size: 80, weight: .thin)).foregroundStyle(KZ.dim)
                    }
                }
            } else {
                Text(item.name.prefix(1))
                    .font(.system(size: 80, weight: .thin)).foregroundStyle(KZ.dim)
            }
        }
        .frame(width: 260, height: 260 / KZ.posterRatio)
        .clipShape(RoundedRectangle(cornerRadius: KZ.imgRadius))
    }

    private func infoLine(_ k: String, _ v: String, big: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(k).font(.system(size: 13)).foregroundStyle(KZ.dim)
            Text(v).font(.system(size: big ? 24 : 15, weight: .semibold)).foregroundStyle(KZ.accent)
        }
    }

    private func stars(_ score: Double) -> some View {
        let full = Int(score / 2)
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < full ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(KZ.accent)
            }
        }
    }

    // MARK: Tab 栏（官方五个）
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(InfoTab.allCases) { t in
                Button { tab = t } label: {
                    Text(t.rawValue)
                        .font(.system(size: 15, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? KZ.onAccent : KZ.label)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(tab == t ? KZ.accent : KZ.card.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .focusSection()
        .padding(.top, 6)
    }

    // MARK: 简介 + 标签
    private func infoBlock(_ s: BangumiSubject) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            tabBar

            switch tab {
            case .overview:   overviewContent(s)
            case .comments:   CommentList(comments: comments)
            case .characters: CharacterGrid(characters: characters)
            case .relations:  RelationList(relations: relations)
            case .staff:      StaffList(staff: staff)
            }
        }
    }

    @ViewBuilder
    private func overviewContent(_ s: BangumiSubject) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let summary = s.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("简介").font(.system(size: 22, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(KZ.dim)
                        .lineLimit(showFullSummary ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if summary.count > 120 {
                        Button { showFullSummary.toggle() } label: {
                            Text(showFullSummary ? "收起" : "加载更多")
                                .font(.system(size: 14))
                                .foregroundStyle(KZ.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !s.tags.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("标签").font(.system(size: 22, weight: .semibold))
                    FlowTags(tags: s.tags) { tag in
                        tagRoute = TagRoute(tag: tag)
                    }
                }
            }
        }
    }

    // MARK: 剧集
    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 换源放在剧集旁边，语义更顺：换源 = 换这批剧集
            sourceBar.focusSection()

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("剧集").font(.system(size: 22, weight: .semibold))
                Text("\(chapters.count) 集 · \(currentSource?.name ?? "-")")
                    .font(.system(size: 13)).foregroundStyle(KZ.dim)
            }

            if loading {
                HStack(spacing: 10) { ProgressView(); Text("读取中…").foregroundStyle(KZ.dim) }
                    .padding(.vertical, 20)
            } else if chapters.isEmpty {
                Text(status).foregroundStyle(KZ.dim).padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(chapters) { ch in
                        ChapterButton(chapter: ch) { Task { await resolve(ch) } }
                    }
                }
                .focusSection()
            }
        }
    }

    // MARK: 数据
    private func load() async {
        loading = true
        defer { loading = false }

        // Bangumi 信息（并行，失败不影响剧集）
        async let bgm: BangumiSubject? = try? await BangumiAPI.findSubject(named: item.name)

        // 多源扫描
        status = "正在搜索可用播放源…"
        await matcher.scan(name: item.name)

        if matcher.hits.isEmpty {
            status = "所有源都没搜到这部番"
            chapterError = true
        } else {
            // 优先用传入的源
            let prefer = matcher.hits.first { $0.id == initialRule?.name } ?? matcher.hits[0]
            await selectSource(prefer)
        }

        subject = await bgm

        if let id = subject?.id {
            async let c1: [BgmComment] = (try? await BangumiAPI.comments(id)) ?? []
            async let c2: [BgmCharacter] = (try? await BangumiAPI.characters(id)) ?? []
            async let c3: [BgmRelation] = (try? await BangumiAPI.relations(id)) ?? []
            async let c4: [BgmStaff] = (try? await BangumiAPI.staff(id)) ?? []
            comments = await c1
            characters = await c2
            relations = await c3
            staff = await c4
        }
    }

    /// 切换播放源
    private func selectSource(_ hit: SourceMatcher.Hit) async {
        currentSource = XPathSource(rule: hit.rule)
        playItem = hit.item
        chapters = []
        chapterError = false
        do {
            chapters = try await currentSource!.chapters(hit.item)
            status = "共 \(chapters.count) 集 · \(hit.rule.name)"
        } catch {
            status = "\(hit.rule.name) 读取剧集失败"
            chapterError = true
        }
    }

    private func resolve(_ ch: Chapter) async {
        guard let src = currentSource else {
            status = "还没有选中播放源"
            return
        }
        status = "正在解析「\(ch.name)」…"
        do {
            let t = try await src.resolve(ch)
            target = t
            status = "已解析到地址，正在打开播放器…"
            playRoute = PlayRoute(target: t, title: ch.name)
        } catch {
            status = "解析失败：\(error.localizedDescription)"
        }
    }
}

/// 标签云：点任意标签 → 按该标签搜索（对齐官方 InfoPage）
struct FlowTags: View {
    let tags: [(String, Int)]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(tags.indices), id: \.self) { i in
                let item = tags[i]
                Button {
                    onTap(item.0)
                } label: {
                    HStack(spacing: 6) {
                        Text(item.0).font(.system(size: 14))
                        Text("\(item.1)").font(.system(size: 12)).foregroundStyle(KZ.dim)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(KZ.card))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// 标签跳转参数（用 item 方式传，避免闭包捕获旧 state）
struct TagRoute: Identifiable {
    let id = UUID()
    let tag: String
}


/// 播放跳转参数
struct PlayRoute: Identifiable {
    let id = UUID()
    let target: PlaybackTarget
    let title: String
}
