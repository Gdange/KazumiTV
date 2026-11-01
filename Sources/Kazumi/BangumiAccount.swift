import Foundation

/// Bangumi 账号与收藏同步
/// 官方走 POST /v0/users/-/collections/{id}（Bearer token）
enum BangumiAccount {
    private static let tokenKey = "bgm.accessToken"
    private static let userKey  = "bgm.username"

    static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    static var username: String? {
        get { UserDefaults.standard.string(forKey: userKey) }
        set { UserDefaults.standard.set(newValue, forKey: userKey) }
    }

    static var isLoggedIn: Bool { (token?.isEmpty == false) }

    static func logout() {
        token = nil
        username = nil
    }
}

/// 收藏类型（对应 Bangumi 的 type 值）
enum BgmCollectType: Int, CaseIterable {
    case wish = 1, done = 2, doing = 3, onHold = 4, dropped = 5

    var label: String {
        switch self {
        case .wish: return "想看"
        case .done: return "看过"
        case .doing: return "在看"
        case .onHold: return "搁置"
        case .dropped: return "抛弃"
        }
    }
}

extension BangumiAPI {

    /// 写收藏（类型 / 评分 / 短评 / 标签，都可选）
    @discardableResult
    static func setCollection(
        subjectID: Int,
        type: BgmCollectType? = nil,
        rate: Int? = nil,
        comment: String? = nil,
        tags: [String]? = nil
    ) async -> Bool {
        guard let token = BangumiAccount.token, !token.isEmpty else { return false }

        var body: [String: Any] = [:]
        if let type { body["type"] = type.rawValue }
        if let rate, rate > 0 { body["rate"] = min(max(rate, 1), 10) }
        if let comment { body["comment"] = String(comment.prefix(380)) }
        if let tags, !tags.isEmpty { body["tags"] = Array(tags.prefix(10)) }
        guard !body.isEmpty else { return false }

        // 官方用的是鉴权镜像
        guard let u = URL(string: "https://api.bgmapi.com/v0/users/-/collections/\(subjectID)") else { return false }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("KazumiTV/0.1 (https://github.com/Predidit/Kazumi)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// 校验 token 并取用户名（/v0/me）
    static func me(token: String) async -> String? {
        guard let u = URL(string: "https://api.bgmapi.com/v0/me") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("KazumiTV/0.1 (https://github.com/Predidit/Kazumi)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (obj["nickname"] as? String) ?? (obj["username"] as? String)
    }

    /// 拉取账号的收藏列表（用于追番同步）
    static func collections(username: String, limit: Int = 50, offset: Int = 0) async -> [(Int, BgmCollectType)] {
        guard let u = URL(string: "https://api.bgm.tv/v0/users/\(username)/collections?subject_type=2&limit=\(limit)&offset=\(offset)") else { return [] }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue("KazumiTV/0.1 (https://github.com/Predidit/Kazumi)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["data"] as? [[String: Any]]
        else { return [] }

        return arr.compactMap { c in
            guard let sub = c["subject"] as? [String: Any],
                  let sid = sub["id"] as? Int,
                  let t = c["type"] as? Int,
                  let type = BgmCollectType(rawValue: t) else { return nil }
            return (sid, type)
        }
    }
}
