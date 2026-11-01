import SwiftUI

/// 追番：状态分类 + 网格/列表切换（对齐官方 CollectPage）
struct CollectionView: View {
    @StateObject private var store = CollectionStore.shared
    @StateObject private var route = DetailRoute()
    @State private var filter: CollectStatus? = .watching   // nil = 全部
    @State private var grid = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: KZ.cardSpace), count: KZ.columns)

    private var list: [CollectedShow] { store.items(status: filter) }

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
        VStack(alignment: .leading, spacing: 18) {
            header
            statusBar.focusSection()
            countRow
            content
        }
        .padding(.horizontal, 60).padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KZ.bg.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("追番").font(.system(size: 40, weight: .bold))
            Spacer()
            Button {
                // Bangumi 同步需要 OAuth，tvOS 无浏览器回调 —— 见报告
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 15))
                    Text("同步").font(.system(size: 15))
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(KZ.card))
                .foregroundStyle(KZ.dim)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            chip("全部", value: nil)
            ForEach(CollectStatus.allCases) { st in
                chip(st.label, value: st)
            }
            Spacer()
        }
    }

    private func chip(_ label: String, value: CollectStatus?) -> some View {
        let selected = filter == value
        return Button { filter = value } label: {
            Text(label)
                .font(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? KZ.onAccent : KZ.label)
                .padding(.horizontal, 18).padding(.vertical, 7)
                .background(Capsule().fill(selected ? KZ.accent : KZ.card))
        }
        .buttonStyle(.plain)
    }

    private var countRow: some View {
        HStack {
            Text("\(list.count) 部").font(.system(size: 14)).foregroundStyle(KZ.dim)
            Spacer()
            Button { grid.toggle() } label: {
                Image(systemName: grid ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 15))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(KZ.card))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if list.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(KZ.dim)
                Text(filter == nil ? "还没有追番" : "还没有\(filter!.label)的番剧")
                    .font(.system(size: 22, weight: .medium))
                Text("在详情页点 ♥ 加入追番")
                    .font(.system(size: 15)).foregroundStyle(KZ.dim)
            }
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            ScrollView {
                if grid {
                    LazyVGrid(columns: columns, spacing: 26) {
                        ForEach(list) { show in
                            CollectedCard(show: show) {
                                Task { await route.open(name: show.name) }
                            }
                        }
                    }
                    .padding(.bottom, 50)
                } else {
                    VStack(spacing: 10) {
                        ForEach(list) { show in
                            ListRow(show: show) {
                                Task { await route.open(name: show.name) }
                            }
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }
}

struct ListRow: View {
    let show: CollectedShow
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(KZ.card)
                if let s = show.poster, let u = URL(string: s) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { Text(show.name.prefix(1)).foregroundStyle(KZ.dim) }
                    }
                }
            }
            .frame(width: 56, height: 56 / KZ.posterRatio)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(show.name).font(.system(size: 17)).lineLimit(1)
            Spacer()
            Text(show.status.label)
                .font(.system(size: 13))
                .foregroundStyle(KZ.accent)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(KZ.accent.opacity(0.14)))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(focused ? KZ.card : KZ.card))
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}

struct CollectedCard: View {
    let show: CollectedShow
    let onTap: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: KZ.imgRadius).fill(KZ.card)
                    if let s = show.poster, let u = URL(string: s) {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Text(show.name.prefix(1))
                                    .font(.system(size: 52, weight: .thin))
                                    .foregroundStyle(KZ.dim)
                            }
                        }
                    } else {
                        Text(show.name.prefix(1))
                            .font(.system(size: 52, weight: .thin))
                            .foregroundStyle(KZ.dim)
                    }
                }
                .aspectRatio(1/KZ.posterRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: KZ.imgRadius))
                .focusCard(focused)

                VStack(alignment: .leading, spacing: 4) {
                    Text(show.name).font(.system(size: 16)).lineLimit(2).foregroundStyle(KZ.label)
                    Text(show.status.label)
                        .font(.system(size: 12))
                        .foregroundStyle(KZ.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
