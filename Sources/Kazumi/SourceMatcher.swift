import Foundation

/// 多源匹配：打开详情页时，并发问所有规则源「你这有没有这部番」
@MainActor
final class SourceMatcher: ObservableObject {

    struct Hit: Identifiable {
        let id: String        // 规则名
        let rule: KazumiRule
        let item: MediaItem
    }

    @Published private(set) var hits: [Hit] = []
    @Published private(set) var scanning = false

    /// 并发搜索所有已装规则
    func scan(name: String) async {
        guard !scanning else { return }
        scanning = true
        hits = []
        defer { scanning = false }

        let rules = RuleCatalog.installed().map(\.rule)

        await withTaskGroup(of: Hit?.self) { group in
            for rule in rules {
                group.addTask {
                    let src = XPathSource(rule: rule)
                    guard let list = try? await src.search(name), let first = list.first
                    else { return nil }
                    return Hit(id: rule.name, rule: rule, item: first)
                }
            }
            for await r in group {
                if let r { hits.append(r) }
            }
        }
        // 按规则名排序，结果稳定
        hits.sort { $0.id < $1.id }
    }
}
