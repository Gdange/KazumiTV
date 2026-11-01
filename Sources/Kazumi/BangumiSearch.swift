import Foundation

/// Bangumi 番剧搜索（支持 tag / sort / 评分 / 排名 / 档期）
struct BgmSearchItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let nameCN: String?
    let image: String?
    let score: Double?
    let date: String?
    var displayName: String { (nameCN?.isEmpty == false ? nameCN! : name) }
    var year: String {
        guard let d = date, d.count >= 4 else { return "" }
        return String(d.prefix(4))
    }
}

extension BangumiAPI {

    static func search(_ q: SearchQuery, limit: Int = 24, offset: Int = 0) async throws -> [BgmSearchItem] {
        guard let u = URL(string: "https://api.bgm.tv/v0/search/subjects?limit=\(limit)&offset=\(offset)")
        else { return [] }

        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("KazumiTV/0.1 (tvOS)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var filter: [String: Any] = ["type": [2], "nsfw": q.nsfw]
        if !q.tags.isEmpty { filter["tag"] = q.tags }
        if let (lo, hi) = q.rankRange { filter["rank"] = [">\(lo)", "<=\(hi)"] }
        if let (lo, hi) = q.scoreRange { filter["rating"] = [">\(lo)", "<=\(hi)"] }
        if let (a, b) = q.dateRange { filter["air_date"] = [">=\(a)", "<=\(b)"] }
        if let season = q.season { filter["air_date"] = seasonDates(season) }

        let sort = ["match": "match", "heat": "heat", "rank": "rank", "score": "score"][q.sort] ?? "match"

        let body: [String: Any] = ["keyword": q.keyword, "sort": sort, "filter": filter]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "bgm", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Bangumi 返回 HTTP \(http.statusCode)"])
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { return [] }

        return rows.compactMap { r in
            guard let id = r["id"] as? Int else { return nil }
            let images = r["images"] as? [String: Any]
            let rating = r["rating"] as? [String: Any]
            return BgmSearchItem(
                id: id,
                name: r["name"] as? String ?? "",
                nameCN: (r["name_cn"] as? String) ?? (r["nameCN"] as? String),
                image: (images?["large"] as? String) ?? (images?["common"] as? String),
                score: rating?["score"] as? Double,
                date: r["date"] as? String ?? (r["air_date"] as? String)
            )
        }
    }

    /// 2024Q4 → ["2024-10-01", "2024-12-31"]
    private static func seasonDates(_ season: String) -> [String] {
        let parts = season.uppercased().components(separatedBy: "Q")
        guard parts.count == 2, let year = Int(parts[0]), let q = Int(parts[1]) else { return [] }
        let ranges = [(1, 3, "01-01", "03-31"), (4, 6, "04-01", "06-30"),
                      (7, 9, "07-01", "09-30"), (10, 12, "10-01", "12-31")]
        guard q >= 1, q <= 4 else { return [] }
        let r = ranges[q - 1]
        return [">=\(year)-\(r.2)", "<=\(year)-\(r.3)"]
    }
}
