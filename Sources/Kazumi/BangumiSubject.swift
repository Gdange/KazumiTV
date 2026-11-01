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
    var alias: [String] = []         // 别名（中文名/日文名/英文名）
    var airWeekday: Int = 0          // 放送星期 1–7
    var type: Int = 2                // 条目类型（2 = 动画）

    var displayName: String {
        if let cn = nameCN, !cn.isEmpty { return cn }
        return name
    }
}

extension BangumiAPI {

    /// 端点 /p1/subjects/{id}
    static func subject(id: Int, useCache: Bool = true) async throws -> BangumiSubject? {
        // 先看磁盘缓存（7 天内直接返回，秒开 + 离线可用）
        if useCache, let cached = await BangumiCache.shared.get(id), let s = parseSubject(cached) {
            // 后台静默刷新
            Task { try? await refresh(id) }
            return s
        }
        return try await refresh(id)
    }

    @discardableResult
    private static func refresh(_ id: Int) async throws -> BangumiSubject? {
        guard let u = URL(string: "https://next.bgm.tv/p1/subjects/\(id)") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue("KazumiTV/0.1 (tvOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        await BangumiCache.shared.put(id, data)
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

    /// 「星期一」/「周一」/「Mon」→ 1–7
    private static func parseWeekday(_ s: String) -> Int {
        let map = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]
        for (k, v) in map where s.contains(k) { return v }
        let en = ["mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7]
        let low = s.lowercased()
        for (k, v) in en where low.hasPrefix(k) { return v }
        return 0
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
        // infobox：别名、放送星期
        var alias: [String] = []
        var weekday = 0
        if let box = d["infobox"] as? [[String: Any]] {
            for item in box {
                guard let key = item["key"] as? String else { continue }
                let values = (item["values"] as? [[String: Any]])?.compactMap { $0["v"] as? String } ?? []
                if key == "别名" {
                    alias.append(contentsOf: values.filter { !$0.isEmpty })
                } else if key == "放送星期" || key == "放送日" {
                    if let v = values.first { weekday = parseWeekday(v) }
                }
            }
        }

        var subj = BangumiSubject(
            id: id,
            name: d["name"] as? String ?? "",
            nameCN: d["nameCN"] as? String ?? d["name_cn"] as? String,
            summary: d["summary"] as? String,
            date: d["date"] as? String,
            score: rating?["score"] as? Double,
            rank: rating?["rank"] as? Int,
            ratingTotal: rating?["total"] as? Int,
            image: (images?["common"] as? String) ?? (images?["large"] as? String),
            tags: tags,
            scoreCounts: (rating?["count"] as? [Int]) ?? []
        )
        subj.alias = alias
        subj.airWeekday = weekday
        subj.type = d["type"] as? Int ?? 2
        return subj
    }
}
