import SwiftUI

/// 时间表：周历条 + 番组列表（对齐官方 SchedulePage）
struct ScheduleView: View {
    @StateObject private var route = DetailRoute()
    @State private var week: [[BangumiItem]] = []
    @State private var dayIndex = 0
    @State private var status = "正在读取放送表…"

    /// 官方顺序：周一到周日，最后是「今天」
    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private var todayIndex: Int {
        let wd = Calendar.current.component(.weekday, from: Date())   // 1=周日
        return (wd + 5) % 7                                           // 0=周一
    }

    private var currentList: [BangumiItem] {
        week.indices.contains(dayIndex) ? week[dayIndex] : []
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
            header
            weekBar.focusSection()
            countRow
            content
        }
        .padding(.horizontal, 60).padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KZ.bg.ignoresSafeArea())
        .task {
            await load()
            prefetchCurrentDay()
        }
        .onChange(of: dayIndex) { _, _ in prefetchCurrentDay() }
    }

    /// 只预取当前这一天的封面，切天时再补
    private func prefetchCurrentDay() {
        guard week.indices.contains(dayIndex) else { return }
        ImagePrefetcher.prefetch(week[dayIndex].compactMap { $0.image }, limit: 18)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(seasonTitle).font(.system(size: 34, weight: .bold))
                .foregroundStyle(KZ.label)
            Image(systemName: "chevron.down")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(KZ.dim)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 13))
                Text("热度优先").font(.system(size: 14))
            }
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Capsule().fill(KZ.card))
            .foregroundStyle(KZ.dim)
        }
    }

    private var seasonTitle: String {
        let now = Date()
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let season = ["冬季", "春季", "夏季", "秋季"][min(3, (month - 1) / 3)]
        return "\(year)年\(season)"
    }

    /// 周历条：每天显示日期 + 番组数，「今天」高亮
    private var weekBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                weekChip(i)
            }
        }
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14).fill(KZ.card.opacity(0.55)))
    }

    private func weekChip(_ i: Int) -> some View {
        WeekChip(index: i,
                 label: i == todayIndex ? "今天" : dayNames[i],
                 count: week.indices.contains(i) ? week[i].count : 0,
                 selected: i == dayIndex) { dayIndex = i }
    }

    private func weekChipOld(_ i: Int) -> some View {
        let isToday = i == todayIndex
        let isSel = i == dayIndex
        return Button { dayIndex = i } label: {
            VStack(spacing: 4) {
                Text(isToday ? "今天" : dayNames[i])
                    .font(.system(size: 15, weight: isSel ? .semibold : .regular))
                Text("\(week.indices.contains(i) ? week[i].count : 0)")
                    .font(.system(size: 13))
                    .opacity(0.7)
            }
            .foregroundStyle(isSel ? KZ.onAccent : KZ.label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSel ? KZ.accent : .clear)
            )
            .scaleEffect(isSel ? 1.0 : 0.96)
            .animation(.easeOut(duration: 0.15), value: isSel)
        }
        .buttonStyle(.plain)
    }

    private var countRow: some View {
        HStack {
            Text("\(currentList.count) 部").font(.system(size: 14)).foregroundStyle(KZ.dim)
            Spacer()
            Text(status).font(.system(size: 13)).foregroundStyle(KZ.dim)
        }
    }

    @ViewBuilder
    private var content: some View {
        if currentList.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "calendar").font(.system(size: 54, weight: .thin)).foregroundStyle(KZ.dim)
                Text(dayIndex == todayIndex ? "今天没有放送" : "这天没有放送")
                    .font(.system(size: 18)).foregroundStyle(KZ.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 360)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(currentList) { item in
                        ScheduleRow(item: item) {
                            Task { await route.open(name: item.displayName) }
                        }
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }

    private func load() async {
        do {
            week = try await BangumiAPI.calendar()
            dayIndex = todayIndex
            status = "共 \(week.reduce(0) { $0 + $1.count }) 部放送中"
        } catch {
            status = "读取失败：\(error.localizedDescription)"
        }
    }
}

/// 列表行：海报 + 标题 + 信息 + 评分（对齐官方条目卡片）
struct ScheduleRow: View {
    let item: BangumiItem
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(KZ.card)
                if let s = item.image, let u = URL(string: s) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Text(item.displayName.prefix(1))
                                .font(.system(size: 40, weight: .thin)).foregroundStyle(KZ.dim) }
                    }
                } else {
                    Text(item.displayName.prefix(1))
                        .font(.system(size: 40, weight: .thin)).foregroundStyle(KZ.dim)
                }
            }
            .frame(width: 96, height: 96 / KZ.posterRatio)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 10) {
                Text(item.displayName)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(KZ.label)
                    .lineLimit(2)

                if let info = item.info, !info.isEmpty {
                    Text(shortInfo(info))
                        .font(.system(size: 13))
                        .foregroundStyle(KZ.dim)
                        .lineLimit(1)
                }

                if let score = item.score, score > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill").font(.system(size: 11))
                        Text(String(format: "%.1f", score)).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(KZ.onAccent)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(KZ.accent.opacity(0.85)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14)
            .fill(focused ? KZ.card : KZ.card.opacity(0.6)))
        .scaleEffect(focused ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }

    /// 官方那行是「12 话 · 喜剧 · TV」，从 info 里拆出来
    private func shortInfo(_ raw: String) -> String {
        let parts = raw.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2 {
            return parts.dropFirst().prefix(2).joined(separator: " · ")
        }
        return raw
    }
}


/// 可聚焦的星期按钮
struct WeekChip: View {
    let index: Int
    let label: String
    let count: Int
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 13))
                    .opacity(0.7)
            }
            .foregroundStyle(selected ? KZ.onAccent : KZ.label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? KZ.accent : (focused ? KZ.accent.opacity(0.15) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2.5)
            )
            .scaleEffect(focused ? 1.05 : (selected ? 1.0 : 0.96))
            .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
