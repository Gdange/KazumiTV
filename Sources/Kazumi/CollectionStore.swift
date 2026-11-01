import Foundation
import SwiftUI

/// 追番收藏（本地持久化）
/// 收藏状态（对齐官方 CollectType）
enum CollectStatus: Int, Codable, CaseIterable, Identifiable {
    case watching = 1       // 在看
    case planToWatch = 2    // 想看
    case completed = 3      // 看过
    case onHold = 4         // 搁置
    case dropped = 5        // 抛弃

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .watching: return "在看"
        case .planToWatch: return "想看"
        case .completed: return "看过"
        case .onHold: return "搁置"
        case .dropped: return "抛弃"
        }
    }
}

struct CollectedShow: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String          // sourceID + href
    let name: String
    let href: String
    let poster: String?
    let sourceID: String
    var addedAt: Date
    var status: CollectStatus = .watching

    enum CodingKeys: String, CodingKey {
        case key, name, href, poster, sourceID, addedAt, status
    }
}

@MainActor
final class CollectionStore: ObservableObject {
    static let shared = CollectionStore()

    @Published private(set) var items: [CollectedShow] = []
    private let key = "kazumi.collection.v1"

    private init() { load() }

    func contains(_ item: MediaItem) -> Bool {
        items.contains { $0.key == "\(item.sourceID)|\(item.href)" }
    }

    func items(status: CollectStatus?) -> [CollectedShow] {
        guard let status else { return items }
        return items.filter { $0.status == status }
    }

    func setStatus(_ show: CollectedShow, to status: CollectStatus) {
        guard let i = items.firstIndex(where: { $0.key == show.key }) else { return }
        items[i].status = status
        save()
    }

    /// 查询某条目的收藏状态
    func status(of item: MediaItem) -> CollectStatus? {
        items.first { $0.key == "\(item.sourceID)|\(item.href)" }?.status
    }

    /// 直接设置状态（不存在则新建）
    func setStatus(_ item: MediaItem, to status: CollectStatus) {
        let k = "\(item.sourceID)|\(item.href)"
        if let i = items.firstIndex(where: { $0.key == k }) {
            items[i].status = status
        } else {
            items.insert(CollectedShow(key: k, name: item.name, href: item.href,
                                       poster: item.poster, sourceID: item.sourceID,
                                       addedAt: Date(), status: status), at: 0)
        }
        save()
    }

    func removeByItem(_ item: MediaItem) {
        items.removeAll { $0.key == "\(item.sourceID)|\(item.href)" }
        save()
    }

    func toggle(_ item: MediaItem) {
        let k = "\(item.sourceID)|\(item.href)"
        if let idx = items.firstIndex(where: { $0.key == k }) {
            items.remove(at: idx)
        } else {
            items.insert(CollectedShow(key: k, name: item.name, href: item.href,
                                       poster: item.poster, sourceID: item.sourceID,
                                       addedAt: Date(), status: .watching), at: 0)
        }
        save()
    }

    func remove(_ show: CollectedShow) {
        items.removeAll { $0.key == show.key }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([CollectedShow].self, from: data)
        else { return }
        items = list
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
