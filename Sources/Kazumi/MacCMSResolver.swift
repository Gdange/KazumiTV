import Foundation

/// MacCMS（苹果CMS）播放页解析器
///
/// 链路（全部纯 HTTP，不需要 JS 引擎）：
///   ① 播放页里 `var player_aaaa={"url":"Doki-...","from":"YDY","encrypt":0}`
///   ② `playerconfig.js` 里 `player_list[from].parse` 给出解析器地址
///   ③ 请求解析器 → 返回 `config={url,key,time}`
///   ④ POST `api_config.php` → 明文 m3u8/mp4
enum MacCMSResolver {

    struct Result {
        let url: URL
        let headers: [String: String]
    }

    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // MARK: 入口

    static func resolve(playPage url: URL) async throws -> Result {
        let html = try await get(url.absoluteString, referer: nil)

        guard let player = extractPlayerJSON(html) else {
            throw Err.noPlayerData
        }

        // 直链：url 本身就是媒体地址
        if let raw = player["url"] as? String, isMedia(raw) {
            guard let u = URL(string: raw) else { throw Err.badURL }
            return Result(url: u, headers: ["User-Agent": ua, "Referer": url.absoluteString])
        }

        guard let encUrl = player["url"] as? String else { throw Err.noPlayerData }

        // encrypt: 2 —— base64 后再 URL 编码，纯前端可解（7sefun 等站用这个）
        if let enc = player["encrypt"] as? Int, enc == 2 {
            if let decoded = decodeEncrypt2(encUrl), let u = URL(string: decoded) {
                return Result(url: u, headers: ["User-Agent": ua, "Referer": url.absoluteString])
            }
        }

        // encrypt: 1 —— base64 后字符位移
        if let enc = player["encrypt"] as? Int, enc == 1 {
            if let decoded = decodeEncrypt1(encUrl), let u = URL(string: decoded) {
                return Result(url: u, headers: ["User-Agent": ua, "Referer": url.absoluteString])
            }
        }

        guard let from = player["from"] as? String else { throw Err.noPlayerData }

        // 找解析器地址
        guard let parserBase = try await findParser(from: from, pageHost: url) else {
            throw Err.noParser(from)
        }

        // 解析器页面
        let parserURL = parserBase + encUrl
        let parserHTML = try await get(parserURL, referer: url.absoluteString)

        guard let cfg = extractConfig(parserHTML) else {
            throw Err.noConfig
        }

        if let u = cfg["url"], isMedia(u) {
            guard let url = URL(string: u) else { throw Err.badURL }
            return Result(url: url, headers: ["User-Agent": ua, "Referer": parserURL])
        }

        // 服务端解密
        guard let apiBase = URL(string: parserURL) else { throw Err.badURL }
        let api = apiBase.scheme! + "://" + (apiBase.host ?? "") + "/api_config.php"

        let form = [
            "url": cfg["url"] ?? "",
            "time": cfg["time"] ?? "",
            "key": cfg["key"] ?? "",
            "title": ""
        ]
        let json = try await postForm(api, form: form, referer: parserURL)
        guard let real = json["url"] as? String, !real.isEmpty else {
            throw Err.apiFailed((json["msg"] as? String) ?? "接口没返回地址")
        }
        guard let finalURL = URL(string: real) else { throw Err.badURL }

        var headers = ["User-Agent": (json["user-agent"] as? String) ?? ua]
        if let ref = json["referer"] as? String, !ref.isEmpty { headers["Referer"] = ref }
        return Result(url: finalURL, headers: headers)
    }

    // MARK: 解密

    /// encrypt = 2：base64 → URLDecode
    private static func decodeEncrypt2(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 补齐 base64 padding
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.removingPercentEncoding ?? text
    }

    /// encrypt = 1：base64 → 每个字符码点 +2 → URLDecode（MacCMS 老式混淆）
    private static func decodeEncrypt1(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        var shifted = ""
        for ch in text.unicodeScalars {
            if let v = UnicodeScalar(ch.value &+ 2) { shifted.unicodeScalars.append(v) }
        }
        return (shifted.removingPercentEncoding ?? shifted)
    }

    // MARK: 提取

    /// 从播放页抓 `var player_aaaa={...}`
    private static func extractPlayerJSON(_ html: String) -> [String: Any]? {
        guard let start = html.range(of: "player_aaaa=")?.upperBound else { return nil }
        let rest = html[start...]
        guard let jsonText = sliceJSON(rest) else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(jsonText.utf8))) as? [String: Any]
    }

    /// 从解析器页面抓 `var config = {...}`
    private static func extractConfig(_ html: String) -> [String: String]? {
        guard let start = html.range(of: "var config")?.upperBound else { return nil }
        let rest = html[start...]
        guard let jsonText = sliceJSON(rest) else { return nil }
        guard let d = (try? JSONSerialization.jsonObject(with: Data(jsonText.utf8))) as? [String: Any]
        else { return nil }
        var out: [String: String] = [:]
        for (k, v) in d {
            if let s = v as? String { out[k] = s }
            else if let n = v as? NSNumber { out[k] = n.stringValue }
        }
        return out
    }

    /// 从 `{` 开始做括号配对，切出完整 JSON
    private static func sliceJSON(_ text: Substring) -> String? {
        guard let open = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString {
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[open...i]) }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    /// 从 playerconfig.js 取 from 对应的解析器地址
    private static func findParser(from: String, pageHost pageURL: URL) async throws -> String? {
        let base = pageURL.scheme! + "://" + (pageURL.host ?? "")
        // 常见路径
        for path in ["/static/js/playerconfig.js", "/static/js/playerconfig.js?t=\(Int(Date().timeIntervalSince1970))"] {
            guard let js = try? await get(base + path, referer: pageURL.absoluteString) else { continue }
            if let p = matchParser(in: js, from: from) { return p }
        }
        return nil
    }

    private static func matchParser(in js: String, from: String) -> String? {
        // "YDY":{"show":"...","parse":"https://xxx/?url="}
        guard let keyRange = js.range(of: "\"\(from)\"") ?? js.range(of: "\(from):") else { return nil }
        let tail = js[keyRange.lowerBound...]
        guard let parseRange = tail.range(of: "\"parse\"") else { return nil }
        let after = tail[parseRange.upperBound...]
        guard let q1 = after.firstIndex(of: "\"") else { return nil }
        let rest = after[after.index(after: q1)...]
        guard let q2 = rest.firstIndex(of: "\"") else { return nil }
        let raw = String(rest[..<q2])
            .replacingOccurrences(of: "\\/", with: "/")
        return raw.isEmpty ? nil : raw
    }

    // MARK: 网络

    private static func get(_ url: String, referer: String?) async throws -> String {
        guard let u = URL(string: url) else { throw Err.badURL }
        var req = URLRequest(url: u)
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        let (data, _) = try await URLSession.shared.data(for: req)
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .init(rawValue: 0x80000632)) { return s }  // GB18030
        return ""
    }

    private static func postForm(_ url: String, form: [String: String], referer: String) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw Err.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = form.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? v)"
        }.joined(separator: "&")
        req.httpBody = Data(body.utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func isMedia(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains(".m3u8") || lower.contains(".mp4") || lower.contains(".flv")
    }

    enum Err: LocalizedError {
        case badURL, noPlayerData, noConfig, noParser(String), apiFailed(String)
        var errorDescription: String? {
            switch self {
            case .badURL: return "地址无效"
            case .noPlayerData: return "播放页里没找到 player_aaaa（可能不是 MacCMS）"
            case .noConfig: return "解析器没有返回 config"
            case .noParser(let f): return "找不到 \(f) 对应的解析器"
            case .apiFailed(let m): return "解析接口失败：\(m)"
            }
        }
    }
}
