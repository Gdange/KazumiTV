import Foundation

/// 搜索结果缓存：同一部番在 10 分钟内不重复搜
actor SearchCache {
    static let shared = SearchCache()

    private struct Entry {
        let results: [MediaItem]
        let at: Date
    }
    private var store: [String: Entry] = [:]
    private let ttl: TimeInterval = 600

    private func key(_ source: String, _ keyword: String) -> String {
        "\(source)|\(keyword)"
    }

    func get(source: String, keyword: String) -> [MediaItem]? {
        let k = key(source, keyword)
        guard let e = store[k] else { return nil }
        if Date().timeIntervalSince(e.at) > ttl {
            store.removeValue(forKey: k)
            return nil
        }
        return e.results
    }

    func put(source: String, keyword: String, results: [MediaItem]) {
        store[key(source, keyword)] = Entry(results: results, at: Date())
    }

    func clear() { store.removeAll() }
}
