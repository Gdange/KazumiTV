import SwiftUI

/// 统一的「按名字打开详情」路由
/// 首页/时间表/追番 三处共用：用条目名去当前规则源搜一次，取第一条进详情
@MainActor
final class DetailRoute: ObservableObject {
    @Published var opened: MediaItem?
    @Published var busy = false
    @Published var message: String?

    static let shared = DetailRoute()

    private var rule: KazumiRule {
        RuleCatalog.installed().first?.rule ?? RulesStore.loadBundled().first!
    }

    func open(name: String) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let src = XPathSource(rule: rule)
            let list = try await src.search(name)
            if let first = list.first {
                opened = first
            } else {
                message = "「\(name)」在 \(rule.name) 没搜到，换个源试试"
            }
        } catch {
            message = "打开失败：\(error.localizedDescription)"
        }
    }
}
