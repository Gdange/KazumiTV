import Foundation
import CryptoKit
import SwiftUI

/// 一条弹幕
struct DanmakuEntry: Identifiable, Hashable {
    let id = UUID()
    let time: Double          // 出现秒数
    let text: String
    let colorIndex: Int
    let mode: Int             // 1 滚动 / 4 底部 / 5 顶部
}

/// 弹弹play 开放平台（v2 API，需 AppId + AppSecret 签名）
enum DanmakuAPI {

    private static let host = "https://api.dandanplay.net"

    // MARK: 签名
    /// signature = base64( sha256( AppId + timestamp + path + AppSecret ) )
    private static func sign(appId: String, secret: String, path: String, ts: Int) -> String {
        let data = Data((appId + String(ts) + path + secret).utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }

    private static func get(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        let appId = UserDefaults.standard.string(forKey: "kz.danmakuAppId") ?? ""
        let secret = UserDefaults.standard.string(forKey: "kz.danmakuSecret") ?? ""
        guard !appId.isEmpty, !secret.isEmpty else { throw Err.noCredentials }

        var comp = URLComponents(string: host + path)!
        if !query.isEmpty {
            comp.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comp.url!)
        req.timeoutInterval = 20
        let ts = Int(Date().timeIntervalSince1970)
        req.setValue("KazumiTV/0.1 (tvOS)", forHTTPHeaderField: "User-Agent")
        req.setValue(appId, forHTTPHeaderField: "X-AppId")
        req.setValue(String(ts), forHTTPHeaderField: "X-Timestamp")
        req.setValue(sign(appId: appId, secret: secret, path: path, ts: ts),
                     forHTTPHeaderField: "X-Signature")
        req.setValue("1", forHTTPHeaderField: "X-Auth")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Err.http(http.statusCode, String(body.prefix(120)))
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // MARK: 接口

    /// 按番名搜剧集，返回 (episodeId, 集数) 列表
    static func searchEpisodes(anime: String) async throws -> [(id: Int, ep: Int, title: String)] {
        let json = try await get("/api/v2/search/episodes", query: ["anime": anime, "v2": "true"])
        guard let animes = json["animes"] as? [[String: Any]] else { return [] }
        var out: [(Int, Int, String)] = []
        for a in animes {
            guard let eps = a["episodes"] as? [[String: Any]] else { continue }
            for e in eps {
                guard let eid = e["episodeId"] as? Int else { continue }
                let num = e["episodeNumber"] as? Int ?? 0
                let title = e["episodeTitle"] as? String ?? ""
                out.append((eid, num, title))
            }
        }
        return out
    }

    /// 拉某集的弹幕
    static func comments(episodeId: Int) async throws -> [DanmakuEntry] {
        let json = try await get("/api/v2/comment/\(episodeId)",
                                 query: ["withRelated": "true", "chConvert": "0"])
        guard let list = json["comments"] as? [[String: Any]] else { return [] }
        return list.compactMap { c in
            guard let p = c["p"] as? String, let m = c["m"] as? String else { return nil }
            let parts = p.split(separator: ",")
            guard parts.count >= 4,
                  let time = Double(parts[0]),
                  let mode = Int(parts[1]),
                  let color = Int(parts[2]) else { return nil }
            return DanmakuEntry(time: time, text: m, colorIndex: color, mode: mode)
        }
    }

    enum Err: LocalizedError {
        case noCredentials, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .noCredentials: return "还没填写弹弹play AppId / AppSecret（设置 → 应用）"
            case .http(let c, let msg): return "弹弹play 返回 \(c)：\(msg)"
            }
        }
    }
}
