import Foundation
import SwiftUI

/// 搜索历史（对齐官方 search_history_repository：去重、倒序、可删可清空）
@MainActor
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    @Published private(set) var keywords: [String] = []
    private let key = "kazumi.searchHistory.v1"
    private let maxCount = 30

    private init() { load() }

    func add(_ kw: String) {
        let k = kw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        keywords.removeAll { $0 == k }        // 去重
        keywords.insert(k, at: 0)             // 最近的在前
        if keywords.count > maxCount { keywords = Array(keywords.prefix(maxCount)) }
        save()
    }

    func remove(_ kw: String) {
        keywords.removeAll { $0 == kw }
        save()
    }

    func clear() {
        keywords.removeAll()
        save()
    }

    private func load() {
        keywords = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private func save() {
        UserDefaults.standard.set(keywords, forKey: key)
    }
}

/// 官方分类标签（lib/utils/constants.dart → defaultAnimeTags）
enum AnimeTags {
    static let all: [String] = [
        "日常", "原创", "校园", "搞笑", "奇幻", "百合", "恋爱",
        "悬疑", "热血", "后宫", "机战", "轻改", "偶像", "治愈", "异世界"
    ]
}
