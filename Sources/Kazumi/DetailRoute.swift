import Foundation

/// 统一的「按名字打开详情」路由（首页 / 时间表 / 追番 / 标签页共用）
///
/// 关键约束：**并发搜索 + 总超时**，绝不让用户对着转圈等几十秒。
/// 谁先返回用谁，拿到结果立刻进详情。
@MainActor
final class DetailRoute: ObservableObject {
    @Published var opened: MediaItem?
    @Published var busy = false
    @Published var message: String?

    static let shared = DetailRoute()

    /// 整个查找最多花这么久
    private let budget: Double = 8
    /// 同时问几个源
    private let parallelism = 12

    func open(name: String) async {
        guard !busy else { return }
        busy = true
        message = "正在匹配来源…"
        defer { busy = false }

        let rules = RuleCatalog.installed().map(\.rule)
            .filter { SourceRank.score($0.name) > -6 }
            .sorted { SourceRank.score($0.name) > SourceRank.score($1.name) }
        let variants = Array(XPathSource.searchVariants(name).prefix(2))

        let found = await withTaskGroup(of: (String, MediaItem)?.self) { group -> (String, MediaItem)? in
            var queue = rules.prefix(parallelism * 2)[...]
            var running = 0

            while running < parallelism, let rule = queue.first {
                queue = queue.dropFirst()
                running += 1
                group.addTask { await Self.tryRule(rule, variants: variants) }
            }

            let deadline = Date().addingTimeInterval(budget)
            for await r in group {
                if let r { group.cancelAll(); return r }
                // 补下一个
                if let rule = queue.first {
                    queue = queue.dropFirst()
                    group.addTask { await Self.tryRule(rule, variants: variants) }
                }
                if Date() > deadline { group.cancelAll(); break }
            }
            return nil
        }

        if let (sourceID, item) = found {
            SourceRank.recordSuccess(sourceID)
            message = nil
            opened = item
        } else {
            message = "「\(name)」没在可用源里找到"
        }
    }

    nonisolated private static func tryRule(_ rule: KazumiRule, variants: [String]) async -> (String, MediaItem)? {
        let src = XPathSource(rule: rule)
        for v in variants {
            if let list = try? await src.search(v, fast: true), let first = list.first {
                return (rule.name, first)
            }
        }
        return nil
    }
}
