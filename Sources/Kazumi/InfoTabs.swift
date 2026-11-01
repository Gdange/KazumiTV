import SwiftUI

/// 详情页的五个 Tab（对齐官方 info_page.dart：概览/吐槽/角色/关联/制作人员）
enum InfoTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case comments = "吐槽"
    case characters = "角色"
    case relations = "关联"
    case staff = "制作人员"
    var id: String { rawValue }
}

struct CommentList: View {
    let subjectID: Int?
    let initial: [BgmComment]
    var onWriteReview: (() -> Void)? = nil
    @FocusState private var reviewFocused: Bool

    @State private var extra: [BgmComment] = []
    @State private var total = 0
    @State private var loadingMore = false
    @State private var hasError = false

    private let pageSize = 12

    /// 官方逻辑：公共评论列表里剔除自己的评论（自己的会单独置顶）
    private var items: [BgmComment] {
        let me = BangumiAccount.username
        let filtered = initial + extra
        return Array(filtered.filter { c in
            guard let me, !me.isEmpty else { return true }
            return c.user != me
        }.prefix(shown))
    }
    @State private var shown = 12

    var body: some View {
        Group {
            if items.isEmpty {
                placeholder(loadingMore ? "正在读取吐槽…" : "还没有吐槽")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Button { onWriteReview?() } label: {
                            HStack {
                                Text("下面我简单喵两句").font(.system(size: 15))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13))
                            }
                            .foregroundStyle(KZ.dim)
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card.opacity(0.7)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(reviewFocused ? KZ.accent : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($reviewFocused)
                        .padding(.bottom, 10)

                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                            CommentCard(comment: c)
                            if idx < items.count - 1 { Divider().opacity(0.25) }
                        }

                        if loadingMore {
                            ProgressView().padding(.vertical, 20)
                        } else if shown < (initial.count + extra.count) || shown < total {
                            Button { Task { await loadMore() } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("加载更多（\(shown)/\(total)）")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 26).padding(.vertical, 12)
                                .background(Capsule().fill(KZ.card))
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 22)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .task {
            guard total == 0, let id = subjectID else { return }
            // 取真实总数（用 limit=1 只拿 total，不浪费流量）
            if let r = try? await BangumiAPI.comments(id, limit: 1, offset: 0) {
                total = max(r.total, initial.count)
            } else {
                total = initial.count
            }
        }
    }

    private func loadMore() async {
        // 本地还有缓存就直接多显示 12 条
        let available = initial.count + extra.count
        if shown < available {
            shown = min(shown + 12, available)
            return
        }
        guard !loadingMore, let id = subjectID else { return }
        if total > 0 && available >= total { return }
        loadingMore = true
        hasError = false
        defer { loadingMore = false }
        do {
            let r = try await BangumiAPI.comments(id, limit: pageSize, offset: items.count)
            let existing = Set(items.map(\.id))
            let new = r.items.filter { !existing.contains($0.id) }
            if new.isEmpty && r.items.isEmpty { hasError = true; return }  // 真的到底了
            extra.append(contentsOf: new)
            if r.total > 0 { total = r.total }
            shown = min(shown + 12, initial.count + extra.count)
        } catch {
            hasError = true          // 允许下次重试
        }
    }
}

/// 单条吐槽（对齐官方 CommentsCard：头像 + 昵称 + 日期 + 星级 + 全文）
struct CommentCard: View {
    let comment: BgmComment
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(KZ.card)
                    if let s = comment.avatar, let u = URL(string: s) {
                        CachedImage(url: u, placeholder: comment.user, contentMode: .fill)
                    } else {
                        Text(comment.user.prefix(1))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(KZ.dim)
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.user)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KZ.accent)
                    if !comment.date.isEmpty {
                        Text(relativeTime(comment.date))
                            .font(.system(size: 11)).foregroundStyle(KZ.dim)
                    }
                }

                Spacer()

                if comment.rate > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < comment.rate / 2 ? "star.fill" : "star")
                                .font(.system(size: 11))
                        }
                    }.foregroundStyle(.orange)
                }
            }

            // 官方不截断，全文显示
            Text(comment.text)
                .font(.system(size: 15))
                .foregroundStyle(KZ.label)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focused ? KZ.accent.opacity(0.10) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? KZ.accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .focusable()
        .focused($focused)
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// 单条吐槽：可聚焦，长评论可展开/收起

struct CharacterGrid: View {
    let characters: [BgmCharacter]

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        if characters.isEmpty {
            placeholder("没有角色资料")
        } else {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(characters) { c in
                        FocusableCard(corner: 10) {
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(KZ.card)
                                if let s = c.image, let u = URL(string: s) {
                                    AsyncImage(url: u) { p in
                                        if case .success(let img) = p { img.resizable().scaledToFill() }
                                        else { Text(c.name.prefix(1)).foregroundStyle(KZ.dim) }
                                    }
                                } else {
                                    Text(c.name.prefix(1)).foregroundStyle(KZ.dim)
                                }
                            }
                            .frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text(c.name).font(.system(size: 13)).lineLimit(1)
                            Text(c.relation).font(.system(size: 11)).foregroundStyle(KZ.dim).lineLimit(1)
                        }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct RelationList: View {
    let relations: [BgmRelation]
    @StateObject private var route = DetailRoute()

    var body: some View {
        if relations.isEmpty {
            placeholder("没有关联条目")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(relations) { r in
                        RelationRow(relation: r) {
                            Task { await route.open(name: r.name) }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct RelationRow: View {
    let relation: BgmRelation
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(KZ.card)
                    if let s = relation.image, let u = URL(string: s) {
                        AsyncImage(url: u) { p in
                            if case .success(let img) = p {
                                img.resizable().scaledToFill()
                            } else { EmptyView() }
                        }
                    }
                }
                .frame(width: 44, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(relation.name).font(.system(size: 15))
                    Text(relation.relation).font(.system(size: 12)).foregroundStyle(KZ.dim)
                }
                Spacer()
                if focused {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KZ.accent)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(focused ? KZ.accent.opacity(0.18) : KZ.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2)
            )
            .scaleEffect(focused ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}

struct StaffList: View {
    let staff: [BgmStaff]

    var body: some View {
        if staff.isEmpty {
            placeholder("没有制作人员资料")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(staff) { p in
                        FocusableRow(corner: 10) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(KZ.card)
                                if let s = p.image, let u = URL(string: s) {
                                    AsyncImage(url: u) { ph in
                                        if case .success(let img) = ph {
                                            img.resizable().scaledToFill()
                                        } else { Text(p.name.prefix(1)).foregroundStyle(KZ.dim) }
                                    }
                                } else {
                                    Text(p.name.prefix(1)).font(.system(size: 14)).foregroundStyle(KZ.dim)
                                }
                            }
                            .frame(width: 38, height: 38)
                            .clipShape(Circle())

                            Text(p.name).font(.system(size: 15))
                            Spacer()
                            Text(p.relation).font(.system(size: 13)).foregroundStyle(KZ.dim)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(KZ.card))
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

private func placeholder(_ text: String) -> some View {
    VStack(spacing: 10) {
        Image(systemName: "tray").font(.system(size: 40, weight: .thin)).foregroundStyle(KZ.dim)
        Text(text).font(.system(size: 15)).foregroundStyle(KZ.dim)
    }
    .frame(maxWidth: .infinity, minHeight: 200)
}

/// 纯展卡片的焦点容器：不响应点击，但能进焦点链（tvOS 上否则滚不到）
struct FocusableCard<Content: View>: View {
    var corner: CGFloat = 10
    @ViewBuilder var content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        content()
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(focused ? KZ.accent.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2)
            )
            .scaleEffect(focused ? 1.04 : 1.0)
            .focusable()
            .focused($focused)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// 纯展示行的焦点容器
struct FocusableRow<Content: View>: View {
    var corner: CGFloat = 10
    @ViewBuilder var content: () -> Content
    @FocusState private var focused: Bool

    var body: some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2)
            )
            .focusable()
            .focused($focused)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}


/// 「39分钟前」「2小时前」这种相对时间
func relativeTime(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = f.date(from: iso)
    if date == nil {
        f.formatOptions = [.withInternetDateTime]
        date = f.date(from: iso)
    }
    guard let d = date else { return String(iso.prefix(10)) }

    let sec = -d.timeIntervalSinceNow
    if sec < 60 { return "刚刚" }
    if sec < 3600 { return "\(Int(sec / 60))分钟前" }
    if sec < 86400 { return "\(Int(sec / 3600))小时前" }
    if sec < 86400 * 30 { return "\(Int(sec / 86400))天前" }
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: d)
}
