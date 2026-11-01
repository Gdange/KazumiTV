import SwiftUI

/// 规则管理：官方目录 + 已装规则
struct RuleStoreView: View {
    @State private var catalog: [CatalogItem] = []
    @State private var installed: [InstalledRule] = []
    @State private var status = "正在拉取官方规则目录…"
    @State private var busy = false
    @State private var tab: Tab = .catalog

    enum Tab: String, CaseIterable, Identifiable {
        case catalog = "官方目录"
        case installed = "已安装"
        var id: String { rawValue }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            tabs
            Text(status).font(.system(size: 13)).foregroundStyle(KZ.dim)
            ScrollView {
                if tab == .catalog {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(catalog) { item in row(item) }
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(installed) { item in installedRow(item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task { await refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {

            Text("规则").font(.system(size: 28, weight: .bold))
            Text("来自 KazumiRules 官方仓库").font(.system(size: 13)).foregroundStyle(KZ.dim)
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Label(busy ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 14))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(KZ.card))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private var tabs: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    Text("\(t.rawValue) \(t == .catalog ? catalog.count : installed.count)")
                        .font(.system(size: 14, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? KZ.onAccent : KZ.label)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(tab == t ? KZ.accent : KZ.card))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func row(_ item: CatalogItem) -> some View {
        let has = installed.contains { $0.name == item.name }
        return Button {
            Task { await install(item) }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(has ? KZ.accent : KZ.dim)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 15, weight: .medium))
                    Text("v\(item.version ?? "-")").font(.system(size: 12)).foregroundStyle(KZ.dim)
                }
                Spacer()
                Text(has ? "已装" : "安装")
                    .font(.system(size: 12))
                    .foregroundStyle(has ? KZ.accent : KZ.dim)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 9).fill(KZ.card))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func installedRow(_ item: InstalledRule) -> some View {
        Button {
            RuleCatalog.deleteUserRule(item.name)
            installed = RuleCatalog.installed()
            status = "已删除 \(item.name)"
        } label: {
            HStack(spacing: 12) {
                Circle().fill(KZ.accent).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 15, weight: .medium))
                    Text(item.isBuiltin ? "内置" : "用户导入")
                        .font(.system(size: 12)).foregroundStyle(KZ.dim)
                }
                Spacer()
                if !item.isBuiltin {
                    Text("删除").font(.system(size: 12)).foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 9).fill(KZ.card))
        }
        .buttonStyle(.plain)
        .disabled(busy || item.isBuiltin)
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        installed = RuleCatalog.installed()
        status = "正在拉取官方目录…"
        do {
            catalog = try await RuleCatalog.list()
            status = "官方目录 \(catalog.count) 条 · 本地已装 \(installed.count) 条"
        } catch {
            status = "目录拉取失败：\(error.localizedDescription)"
        }
    }

    private func install(_ item: CatalogItem) async {
        busy = true
        defer { busy = false }
        status = "正在安装 \(item.name)…"
        do {
            let rule = try await RuleCatalog.download(item.name)
            try RuleCatalog.saveUserRule(rule)
            installed = RuleCatalog.installed()
            status = "✅ 已安装 \(item.name)（v\(item.version ?? "-")）"
        } catch {
            status = "安装失败：\(error.localizedDescription)"
        }
    }
}
