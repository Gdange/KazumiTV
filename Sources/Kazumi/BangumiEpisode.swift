import Foundation

/// Bangumi 官方剧集（含正式标题、播出日期、缩略图）
struct BangumiEpisode: Identifiable, Hashable {
    let id: Int
    let sort: Double
    let name: String
    let nameCN: String?
    let airdate: String?
    let image: String?

    var display: String {
        if let cn = nameCN, !cn.isEmpty { return cn }
        return name
    }
}

extension BangumiAPI {
    /// /v0/episodes?subject_id=&offset=&limit=
    static func episodes(subjectID: Int, limit: Int = 100) async -> [BangumiEpisode] {
        var out: [BangumiEpisode] = []
        var offset = 0
        var total: Int? = nil

        while true {
            guard let u = URL(string: "https://api.bgm.tv/v0/episodes?subject_id=\(subjectID)&offset=\(offset)&limit=\(limit)") else { break }
            var req = URLRequest(url: u)
            req.timeoutInterval = 15
            // api.bgm.tv 要求带 UA 标识
            req.setValue("KazumiTV/0.1 (https://github.com/Predidit/Kazumi)", forHTTPHeaderField: "User-Agent")

            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = root["data"] as? [[String: Any]]
            else { break }

            if total == nil { total = root["total"] as? Int }
            if arr.isEmpty { break }

            for e in arr {
                guard let id = e["id"] as? Int else { continue }
                out.append(BangumiEpisode(
                    id: id,
                    sort: (e["sort"] as? Double) ?? Double(e["sort"] as? Int ?? 0),
                    name: e["name"] as? String ?? "",
                    nameCN: e["name_cn"] as? String,
                    airdate: e["airdate"] as? String,
                    image: e["image"] as? String
                ))
            }
            offset += arr.count
            if let t = total, offset >= t { break }
            if out.count > 500 { break }      // 保险上限
        }
        return out
    }
}
