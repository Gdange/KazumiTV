import Foundation

/// Bangumi 条目详情（对齐官方 getBangumiInfoByID）
struct BangumiSubject {
    let id: Int
    let name: String
    let nameCN: String?
    let summary: String?
    let date: String?
    let score: Double?
    let rank: Int?
    let ratingTotal: Int?
    let image: String?
    let tags: [(String, Int)]
    var scoreCounts: [Int] = []      // 索引 0 = 1 分

    var displayName: String {
        if let cn = nameCN, !cn.isEmpty { return cn }
        return name
    }
}

extension BangumiAPI {

    /// 端点 /p1/subjects/{id}
    static func subject(id: Int) async throws -> BangumiSubject? {
        guard let u = URL(string: "https://next.bgm.tv/p1/subjects/\(id)") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue("KazumiTV/0.1 (tvOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return parseSubject(data)
    }

    /// 用名称反查 Bangumi 条目（官方也是这么匹配的）
    static func findSubject(named keyword: String) async throws -> BangumiSubject? {
        guard let u = URL(string: "https://api.bgm.tv/v0/search/subjects?limit=5&offset=0") else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("KazumiTV/0.1 (tvOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyword": keyword,
            "sort": "match",
            "filter": ["type": [2], "nsfw": false]
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]],
              let first = rows.first,
              let id = first["id"] as? Int else { return nil }
        return try await subject(id: id)
    }

    private static func parseSubject(_ data: Data) -> BangumiSubject? {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let id = d["id"] as? Int else { return nil }
        let rating = d["rating"] as? [String: Any]
        let images = d["images"] as? [String: Any]
        var tags: [(String, Int)] = []
        if let raw = d["tags"] as? [[String: Any]] {
            for t in raw.prefix(12) {
                if let n = t["name"] as? String, let c = t["count"] as? Int {
                    tags.append((n, c))
                }
            }
        }
        return BangumiSubject(
            id: id,
            name: d["name"] as? String ?? "",
            nameCN: d["nameCN"] as? String ?? d["name_cn"] as? String,
            summary: d["summary"] as? String,
            date: d["date"] as? String,
            score: rating?["score"] as? Double,
            rank: rating?["rank"] as? Int,
            ratingTotal: rating?["total"] as? Int,
            image: (images?["large"] as? String) ?? (images?["common"] as? String),
            tags: tags,
            scoreCounts: (rating?["count"] as? [Int]) ?? []
        )
    }
}
