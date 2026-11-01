import Foundation

/// MacCMS（苹果CMS）播放解析：全程纯 HTTP，不需要 JS 引擎
///
/// 实测链路（akianime 等站）：
///   ① 播放页内联 `var player_aaaa={..., "url":"Doki-xxx", "from":"YDY"}`
///   ② `playerconfig.js` 里 `player_list[from].parse` = 解析器前缀
///   ③ GET `parse + url` → 页面里 `var config={url,key,time,vkey}`
///   ④ POST `{解析器域名}/api_config.php` → `{code:200, url:"真实地址"}`
enum MacCMSResolver {

    struct Result {
        let url: URL
        let headers: [String: String]
    }

    enum Err: LocalizedError {
        case noPlayer, noParser, noConfig, badResponse(String), badURL
        var errorDescription: String? {
            switch self {
            case .noPlayer:  return "播放页里没有找到播放器参数"
            case .noParser:  return "解析器配置里没有这个播放源"
            case .noConfig:  return "解析器没有返回播放配置"
            case .badResponse(let m): return "解析失败：\(m)"
            case .badURL:    return "解析出的地址无效"
            }
        }
    }

    private static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// 页面缓存：采集站普遍限流（7sefun 连发几次直接返回 0 字节），
    /// 同一 URL 一分钟内只真请求一次
    private static var pageCache: [String: (String, Date)] = [:]
    private static let cacheTTL: TimeInterval = 60
    private static var lastRequestAt: Date = .distantPast
    /// 同一个站的最小请求间隔
    private static let minInterval: TimeInterval = 0.4

    // MARK: 入口

    static func resolve(playPage url: URL) async throws -> Result {
        let html = try await get(url.absoluteString, referer: nil)

        // ①-a iframe 解析器（AGE 这类：页面里没 player_aaaa，直接嵌 jx.xxx/m3u8/?url=...）
        //     必须放在 player_aaaa 检查之前，否则这类站直接死在前置判断上
        if let viaIframe = try? await resolveIframe(html: html, playPage: url) {
            NSLog("[KZ-RESOLVE] %@ via iframe", url.host ?? "?")
            return viaIframe
        }

        // ① player_aaaa
        guard let player = extractJSON(html, after: "player_aaaa") else {
            throw Err.noPlayer
        }

        let mediaURL = (player["url"] as? String) ?? ""

        // 已经是媒体直链
        if isMedia(mediaURL), let u = URL(string: mediaURL) {
            return Result(url: u, headers: baseHeaders(referer: url.absoluteString))
        }

        // 老式 encrypt：1 = base64+位移，2 = base64+urlencode
        if let enc = player["encrypt"] as? Int, enc == 1 || enc == 2 {
            if let dec = decodeLegacy(mediaURL, mode: enc), isMedia(dec), let u = URL(string: dec) {
                return Result(url: u, headers: baseHeaders(referer: url.absoluteString))
            }
        }

        guard let from = player["from"] as? String, !from.isEmpty, !mediaURL.isEmpty else {
            throw Err.noPlayer
        }

        // ①-b 站内播放器（7sefun 这类：from=ndx，解析器为空，走 /addons/dp/player/art.php）
        //     注意 from 的解析器可能为空，这种情况一定要走这里
        if let inner = try? await siteNativePlayer(site: url, from: from, mediaURL: mediaURL, playPage: url) {
            NSLog("[KZ-RESOLVE] %@ via site player", url.host ?? "?")
            return inner
        }

        // ② 找解析器
        let parse = try await parserPrefix(site: url, from: from)

        // ③ 解析器页面 → config
        let resolverURL = parse + mediaURL
        let page = try await get(resolverURL, referer: url.absoluteString)
        guard let cfg = extractJSON(page, after: "config") else { throw Err.noConfig }

        let cfgURL  = (cfg["url"] as? String) ?? mediaURL
        let cfgKey  = (cfg["key"] as? String) ?? ""
        let cfgTime = String(describing: cfg["time"] ?? "")

        // ④ POST api_config.php
        let base = parse.components(separatedBy: "?").first?.components(separatedBy: "/").dropLast().joined(separator: "/") ?? ""
        let api = base + "/api_config.php"

        let body = "url=\(esc(cfgURL))&time=\(esc(cfgTime))&key=\(esc(cfgKey))&title="
        let resp = try await post(api, body: body, referer: resolverURL)

        guard let data = resp.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = obj["code"] as? String, code == "200",
              let final = obj["url"] as? String, let u = URL(string: final)
        else {
            throw Err.badResponse(resp.prefix(120).description)
        }

        var h = baseHeaders(referer: url.absoluteString)
        if let ua = obj["user-agent"] as? String, !ua.isEmpty { h["User-Agent"] = ua }
        return Result(url: u, headers: h)
    }

    // MARK: iframe 解析器

    /// 播放页里直接嵌一个解析器 iframe，请求它就能拿到 m3u8
    private static func resolveIframe(html: String, playPage: URL) async throws -> Result {
        guard let re = try? NSRegularExpression(pattern: "<iframe[^>]+src=[\"']([^\"']+)", options: .caseInsensitive) else {
            throw Err.noPlayer
        }
        let ns = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { throw Err.noPlayer }

        // 逐个 iframe 跟进，把页面里所有候选媒体地址收集起来
        var iframeSrcs: [String] = []
        for m in matches {
            var src = ns.substring(with: m.range(at: 1))
            src = src.replacingOccurrences(of: "&amp;", with: "&")
            if src.hasPrefix("//") { src = "https:" + src }
            iframeSrcs.append(src)
        }
        // 含 /m3u8/ 的 iframe 大概率是播放器，排前面；vip/广告排后面
        iframeSrcs.sort { a, b in
            func score(_ s: String) -> Int {
                let l = s.lowercased()
                if l.contains("/m3u8") { return 0 }
                if l.contains("vip") || l.contains("adposter") { return 2 }
                return 1
            }
            return score(a) < score(b)
        }

        var candidates: [(URL, String)] = []   // (媒体地址, 来源页 referer)
        for src in iframeSrcs {
            guard let page = try? await get(src, referer: playPage.absoluteString) else { continue }

            for u in allMediaURLs(in: page) {
                if !candidates.contains(where: { $0.0 == u }) {
                    candidates.append((u, src))
                }
            }
            // 页面本身就是播放器（没嵌 m3u8 文本）时，也可能直接是 m3u8 地址
            if let u = URL(string: src), src.contains(".m3u8") {
                candidates.append((u, playPage.absoluteString))
            }
            if candidates.count >= 6 { break }
        }
        guard !candidates.isEmpty else { throw Err.noPlayer }

        // 官方判据：实际请求一下，看内容是不是 #EXTM3U / 有效的视频容器
        for (u, ref) in candidates {
            let headers = ["User-Agent": ua, "Referer": ref]
            if await isRealPlaylist(u, headers: headers) {
                NSLog("[KZ-RESOLVE] verified m3u8: " + String(u.absoluteString.prefix(70)))
                return Result(url: u, headers: headers)
            }
        }

        // 没有 m3u8 就退回第一个能拿到非空内容的地址
        for (u, ref) in candidates {
            let headers = ["User-Agent": ua, "Referer": ref]
            if await isRealMedia(u, headers: headers) {
                NSLog("[KZ-RESOLVE] verified media: " + String(u.absoluteString.prefix(70)))
                return Result(url: u, headers: headers)
            }
        }
        throw Err.noPlayer
    }

    /// 页面里所有形似媒体地址的 URL（不按后缀判断，先收全）
    private static func allMediaURLs(in text: String) -> [URL] {
        let cleaned = text.replacingOccurrences(of: "\\/", with: "/")
        let pattern = "https?://[^\"'\\s<>]+"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = cleaned as NSString
        var out: [URL] = []
        for m in re.matches(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
            let s = ns.substring(with: m.range)
            let low = s.lowercased()
            guard low.contains(".m3u8") || low.contains(".mp4") || low.contains(".flv") else { continue }
            if let u = URL(string: s) { out.append(u) }
        }
        return out
    }

    /// 请求前几个字节，判断是否真的是 m3u8 播放列表（官方判据）
    private static func isRealPlaylist(_ url: URL, headers: [String: String]) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        req.setValue("bytes=0-255", forHTTPHeaderField: "Range")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let head = String(data: data.prefix(48), encoding: .utf8) ?? "<binary>"
            NSLog("[KZ-VERIFY] " + String(url.absoluteString.prefix(56)) + " → " + String(http?.statusCode ?? -1) + " " + String(data.count) + "B head=" + head.replacingOccurrences(of: "\n", with: " "))
            return (200..<400).contains(http?.statusCode ?? 0)
                && head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U")
        } catch {
            NSLog("[KZ-VERIFY] " + String(url.absoluteString.prefix(56)) + " → ERR " + error.localizedDescription)
            return false
        }
    }

    /// 是否是可播的视频容器（mp4 的 ftyp / flv 头）
    private static func isRealMedia(_ url: URL, headers: [String: String]) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        req.setValue("bytes=0-63", forHTTPHeaderField: "Range")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<400).contains(http.statusCode),
              data.count >= 8
        else { return false }
        // ISO BMFF: 前 4 字节长度，后 4 字节 "ftyp"
        if data.count >= 8, String(data: data[4..<8], encoding: .ascii) == "ftyp" { return true }
        // FLV
        if String(data: data.prefix(3), encoding: .ascii) == "FLV" { return true }
        return false
    }

    /// 只匹配指定扩展名的媒体地址
    private static func matchMedia(in text: String, ext: String) -> URL? {
        let cleaned = text.replacingOccurrences(of: "\\/", with: "/")
        let pattern = "https?://[^\"'\\s]+\\.\(ext)[^\"'\\s]*"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = cleaned as NSString
        guard let m = re.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return URL(string: ns.substring(with: m.range))
    }

    // MARK: 站内播放器（addons/dp）

    private static func siteNativePlayer(site: URL, from: String, mediaURL: String, playPage: URL) async throws -> Result {
        let root = "\(site.scheme ?? "https")://\(site.host ?? "")"
        // 从播放页 URL 里取 id（/vodplay/38694-2-1.html → 38694）
        let nums = playPage.lastPathComponent.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        guard let id = nums.first else { throw Err.noPlayer }

        let arg = "key=0&id=\(id)&uid=0&from=\(esc(from))&url=\(esc(mediaURL))"
        let candidates = [
            "\(root)/addons/dp/player/art.php?\(arg)&jump=",
            "\(root)/addons/dp/player/index.php?\(arg)",
        ]
        for c in candidates {
            guard let page = try? await get(c, referer: playPage.absoluteString) else { continue }
            // 页面 JS 里会有 url: "http://...mp4"
            if let found = firstMediaURL(in: page) {
                return Result(url: found, headers: [
                    "User-Agent": ua,
                    "Referer": c,
                ])
            }
        }
        throw Err.noPlayer
    }

    /// 从页面文本里找第一个媒体地址（处理 JSON 转义）
    private static func firstMediaURL(in text: String) -> URL? {
        let cleaned = text.replacingOccurrences(of: "\\/", with: "/")
        let patterns = [
            "https?://[^\"'\\s]+\\.m3u8[^\"'\\s]*",
            "https?://[^\"'\\s]+\\.mp4[^\"'\\s]*",
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = cleaned as NSString
            if let m = re.firstMatch(in: cleaned, range: NSRange(location: 0, length: ns.length)) {
                let s = ns.substring(with: m.range)
                if let u = URL(string: s) { return u }
            }
        }
        return nil
    }

    // MARK: 解析器前缀

    private static func parserPrefix(site: URL, from: String) async throws -> String {
        let root = "\(site.scheme ?? "https")://\(site.host ?? "")"
        // 常见位置
        let candidates = [
            "\(root)/static/js/playerconfig.js",
            "\(root)/static/js/playerconfig.js?t=\(Int(Date().timeIntervalSince1970))",
            "\(root)/template/dsn2/static/js/playerconfig.js",
        ]
        for c in candidates {
            guard let js = try? await get(c, referer: site.absoluteString) else { continue }
            guard let list = extractJSON(js, after: "player_list") else { continue }
            if let entry = list[from] as? [String: Any], let parse = entry["parse"] as? String, !parse.isEmpty {
                return parse
            }
        }
        throw Err.noParser
    }

    // MARK: 工具

    /// 从 `xxx = {...}` 里抠出 JSON 对象（允许尾随逗号）
    static func extractJSON(_ text: String, after key: String) -> [String: Any]? {
        guard let r = text.range(of: key) else { return nil }
        let tail = text[r.upperBound...]
        guard let start = tail.firstIndex(of: "{") else { return nil }

        var depth = 0
        var end: String.Index? = nil
        var i = start
        while i < tail.endIndex {
            let c = tail[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { end = tail.index(after: i); break }
            }
            i = tail.index(after: i)
        }
        guard let e = end else { return nil }
        var raw = String(tail[start..<e])
        // 去尾随逗号（JS 允许，JSON 不允许）
        raw = raw.replacingOccurrences(of: ",}", with: "}")
                 .replacingOccurrences(of: ",\n}", with: "}")
                 .replacingOccurrences(of: ", }", with: "}")
        guard let d = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func decodeLegacy(_ s: String, mode: Int) -> String? {
        var t = s
        if mode == 2 {
            t = t.removingPercentEncoding ?? t
        }
        guard let data = Data(base64Encoded: t) else { return nil }
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        if mode == 1 {
            // 字符整体前移一位
            let shifted = raw.unicodeScalars.map { UnicodeScalar($0.value - 1) ?? $0 }
            return String(String.UnicodeScalarView(shifted))
        }
        return raw
    }

    private static func isMedia(_ s: String) -> Bool {
        let l = s.lowercased()
        return l.hasPrefix("http") && (l.contains(".m3u8") || l.contains(".mp4") || l.contains(".flv"))
    }

    /// URL 参数编码：保留 URL 安全字符（含 _ - . ~），只转义会破坏查询串的
    private static func esc(_ s: String) -> String {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&=?#+")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }

    private static func baseHeaders(referer: String) -> [String: String] {
        ["User-Agent": ua, "Referer": referer]
    }

    private static func get(_ url: String, referer: String?) async throws -> String {
        guard let u = URL(string: url) else { throw Err.badURL }
        var req = URLRequest(url: u)
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        if let r = referer { req.setValue(r, forHTTPHeaderField: "Referer") }
        // 缓存命中直接返回
        if let c = pageCache[url], Date().timeIntervalSince(c.1) < cacheTTL {
            NSLog("[KZ-GET] cache " + String(url.prefix(50)))
            return c.0
        }
        // 节流：两次请求之间至少隔 minInterval
        let wait = minInterval - Date().timeIntervalSince(lastRequestAt)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastRequestAt = Date()

        var data = Data()
        var lastErr: Error?
        for attempt in 0..<2 {
            do {
                (data, _) = try await URLSession.shared.data(for: req)
                NSLog("[KZ-GET] ok " + String(url.prefix(56)) + " " + String(data.count) + "B" + (attempt > 0 ? " (retry)" : ""))
                lastErr = nil
                break
            } catch {
                lastErr = error
                NSLog("[KZ-GET] ERR " + String(url.prefix(56)) + " : " + error.localizedDescription)
                if attempt == 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
        }
        if let e = lastErr { throw e }
        var text = ""
        if let s = String(data: data, encoding: .utf8) { text = s }
        else {
            let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            text = String(data: data, encoding: String.Encoding(rawValue: gb)) ?? ""
        }
        if !text.isEmpty { pageCache[url] = (text, Date()) }
        return text
    }

    private static func post(_ url: String, body: String, referer: String) async throws -> String {
        guard let u = URL(string: url) else { throw Err.badURL }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = body.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
