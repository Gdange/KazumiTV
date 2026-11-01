import Foundation

/// Bangumi 条目磁盘缓存（对齐官方的 Hive 持久化）
/// 存原始 JSON，读取时重新解析，避免维护 Codable
actor BangumiCache {
    static let shared = BangumiCache()

    private let dir: URL
    private let ttl: TimeInterval = 60 * 60 * 24 * 7   // 7 天

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("bgm-subjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ id: Int) -> URL {
        dir.appendingPathComponent("\(id).json")
    }

    func get(_ id: Int) -> Data? {
        let f = file(id)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
              let mtime = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(mtime) < ttl
        else { return nil }
        return try? Data(contentsOf: f)
    }

    func put(_ id: Int, _ data: Data) {
        try? data.write(to: file(id))
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
