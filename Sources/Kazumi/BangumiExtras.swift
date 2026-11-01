import Foundation

/// 角色 / 制作人员 / 关联 / 吐槽 —— 对齐官方 InfoPage 的四个 tab
struct BgmCharacter: Identifiable {
    var id: Int
    var name: String
    var relation: String
    var image: String?
    var actors: [String]
}

struct BgmStaff: Identifiable {
    var id: Int
    var name: String
    var relation: String
    var image: String?
}

struct BgmRelation: Identifiable {
    var id: Int
    var name: String
    var relation: String
    var image: String?
}

struct BgmComment: Identifiable {
    var id: Int
    var user: String
    var rate: Int
    var text: String
    var date: String
}

extension BangumiAPI {

    private static func getJSON(_ url: String) async throws -> Any? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue("KazumiTV/0.1 (tvOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// 角色
    static func characters(_ id: Int) async throws -> [BgmCharacter] {
        guard let arr = try await getJSON("https://api.bgm.tv/v0/subjects/\(id)/characters") as? [[String: Any]]
        else { return [] }
        return arr.compactMap { c in
            guard let cid = c["id"] as? Int, let name = c["name"] as? String else { return nil }
            let images = c["images"] as? [String: Any]
            let actors = (c["actors"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            return BgmCharacter(id: cid, name: name,
                                relation: c["relation"] as? String ?? "",
                                image: (images?["large"] as? String) ?? (images?["grid"] as? String),
                                actors: actors)
        }
    }

    /// 制作人员
    static func staff(_ id: Int) async throws -> [BgmStaff] {
        guard let arr = try await getJSON("https://api.bgm.tv/v0/subjects/\(id)/persons") as? [[String: Any]]
        else { return [] }
        return arr.compactMap { p in
            guard let pid = p["id"] as? Int, let name = p["name"] as? String else { return nil }
            let images = p["images"] as? [String: Any]
            return BgmStaff(id: pid, name: name,
                            relation: p["relation"] as? String ?? "",
                            image: (images?["large"] as? String) ?? (images?["grid"] as? String))
        }
    }

    /// 关联条目
    static func relations(_ id: Int) async throws -> [BgmRelation] {
        guard let arr = try await getJSON("https://api.bgm.tv/v0/subjects/\(id)/subjects") as? [[String: Any]]
        else { return [] }
        return arr.compactMap { r in
            guard let rid = r["id"] as? Int, let name = r["name"] as? String else { return nil }
            let images = r["images"] as? [String: Any]
            return BgmRelation(id: rid, name: name,
                               relation: r["relation"] as? String ?? "",
                               image: (images?["large"] as? String) ?? (images?["common"] as? String))
        }
    }

    /// 吐槽（评论）—— 官方用 next.bgm.tv/p1 这套，失败重试 3 次
    static func comments(_ id: Int, limit: Int = 20) async throws -> [BgmComment] {
        var root: [String: Any]?
        for attempt in 0..<3 {
            if let r = try? await getJSON("https://next.bgm.tv/p1/subjects/\(id)/comments?limit=\(limit)&offset=0") as? [String: Any] {
                root = r
                break
            }
            try? await Task.sleep(nanoseconds: UInt64(500_000_000 * (attempt + 1)))
        }
        guard let root, let arr = root["data"] as? [[String: Any]]
        else { return [] }
        return arr.compactMap { c in
            guard let cid = c["id"] as? Int else { return nil }
            let user = (c["user"] as? [String: Any])?["nickname"] as? String ?? "匿名"
            return BgmComment(id: cid, user: user,
                              rate: c["rate"] as? Int ?? 0,
                              text: c["comment"] as? String ?? "",
                              date: (c["updatedAt"] as? String) ?? "")
        }
    }
}
