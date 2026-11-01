import Foundation

/// Bangumi 数据（Kazumi 官方用的同一个接口）
/// 日历：https://next.bgm.tv/p1/calendar
struct BangumiItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let nameCN: String?
    let image: String?
    let info: String?
    var score: Double? = nil
    var rank: Int? = nil

    var displayName: String {
        if let cn = nameCN, !cn.isEmpty { return cn }
        return name
    }
}

enum BangumiAPI {
    private static let host = "https://next.bgm.tv"
    private static let ua = "KazumiTV/0.1 (tvOS)"

    /// 热门番组：优先官方 next.bgm.tv，失败则降级到 api.bgm.tv 搜索
    static func trending(limit: Int = 24, offset: Int = 0) async throws -> [BangumiItem] {
        do {
            return try await trendingNext(limit: limit, offset: offset)
        } catch {
            return try await trendingFallback(limit: limit, offset: offset)
        }
    }

    /// 降级方案：api.bgm.tv 按热度搜索
    private static func trendingFallback(limit: Int, offset: Int) async throws -> [BangumiItem] {
        guard let u = URL(string: "https://api.bgm.tv/v0/search/subjects?limit=\(limit)&offset=\(offset)")
        else { return [] }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyword": "", "sort": "heat",
            "filter": ["type": [2], "nsfw": false]
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return [] }
        return rows.compactMap { r in
            guard let id = r["id"] as? Int else { return nil }
            let images = r["images"] as? [String: Any]
            let rating = r["rating"] as? [String: Any]
            return BangumiItem(
                id: id,
                name: r["name"] as? String ?? "",
                nameCN: (r["name_cn"] as? String) ?? (r["nameCN"] as? String),
                image: (images?["large"] as? String) ?? (images?["common"] as? String),
                info: nil,
                score: rating?["score"] as? Double,
                rank: rating?["rank"] as? Int
            )
        }
    }

    /// 官方 trending 接口
    private static func trendingNext(limit: Int = 24, offset: Int = 0) async throws -> [BangumiItem] {
        var comp = URLComponents(string: host + "/p1/trending/subjects")!
        comp.queryItems = [
            .init(name: "type", value: "2"),
            .init(name: "limit", value: "\(limit)"),
            .init(name: "offset", value: "\(offset)")
        ]
        var req = URLRequest(url: comp.url!)
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return [] }

        var out: [BangumiItem] = []
        for row in rows {
            guard let sub = row["subject"] as? [String: Any],
                  let id = sub["id"] as? Int else { continue }
            let images = sub["images"] as? [String: Any]
            let rating = sub["rating"] as? [String: Any]
            out.append(BangumiItem(
                id: id,
                name: sub["name"] as? String ?? "",
                nameCN: sub["nameCN"] as? String,
                image: (images?["large"] as? String) ?? (images?["common"] as? String),
                info: sub["info"] as? String,
                score: rating?["score"] as? Double,
                rank: rating?["rank"] as? Int
            ))
        }
        return out
    }

    /// 按标签查番组（官方 getBangumiList 的等价实现）
    static func byTag(_ tag: String, rank: Int = 100) async throws -> [BangumiItem] {
        guard let u = URL(string: "https://api.bgm.tv/v0/search/subjects?limit=24&offset=0") else { return [] }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let filter: [String: Any] = [
            "type": [2],
            "tag": [tag],
            "rank": [">\(rank)", "<=99999"],
            "nsfw": false
        ]
        let body: [String: Any] = ["keyword": "", "sort": "rank", "filter": filter]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "bgm", code: http.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return [] }

        return rows.compactMap { sub in
            guard let id = sub["id"] as? Int else { return nil }
            let images = sub["images"] as? [String: Any]
            return BangumiItem(
                id: id,
                name: sub["name"] as? String ?? "",
                nameCN: sub["name_cn"] as? String ?? sub["nameCN"] as? String,
                image: (images?["large"] as? String) ?? (images?["common"] as? String),
                info: nil
            )
        }
    }

    /// 返回 7 天，索引 0 = 周一
    static func calendar() async throws -> [[BangumiItem]] {
        guard let url = URL(string: host + "/p1/calendar") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")

        var data = Data()
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                (data, _) = try await URLSession.shared.data(for: req)
                lastError = nil
                break
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(600_000_000 * (attempt + 1)))
            }
        }
        if let e = lastError { throw e }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var week: [[BangumiItem]] = []
        for day in 1...7 {
            var list: [BangumiItem] = []
            if let arr = root["\(day)"] as? [[String: Any]] {
                for row in arr {
                    guard let sub = row["subject"] as? [String: Any],
                          let id = sub["id"] as? Int else { continue }
                    let images = sub["images"] as? [String: Any]
                    let rating = sub["rating"] as? [String: Any]
                    list.append(BangumiItem(
                        id: id,
                        name: sub["name"] as? String ?? "",
                        nameCN: sub["nameCN"] as? String,
                        image: (images?["large"] as? String) ?? (images?["common"] as? String),
                        info: sub["info"] as? String,
                        score: rating?["score"] as? Double,
                        rank: rating?["rank"] as? Int
                    ))
                }
            }
            week.append(list)
        }
        return week
    }
}
