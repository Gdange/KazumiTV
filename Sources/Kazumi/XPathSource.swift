import Foundation

/// 把一条 Kazumi 规则包装成通用 Source
struct XPathSource: Source {
    let rule: KazumiRule
    private let engine = RuleEngine()

    var id: String { "kazumi.\(rule.name)" }
    var name: String { rule.name }
    var kind: SourceKind { .catalog }

    func search(_ keyword: String) async throws -> [MediaItem] {
        let items = try await engine.search(rule, keyword: keyword)
        return items.map { it in
            var p: String? = nil
            if let raw = it.poster {
                if raw.hasPrefix("//") { p = "https:" + raw }
                else if raw.hasPrefix("http") { p = raw }
                else if let u = rule.absolute(raw) { p = u.absoluteString }
            }
            return MediaItem(name: it.name, href: it.href, poster: p, sourceID: id)
        }
    }

    func chapters(_ item: MediaItem) async throws -> [Chapter] {
        let list = try await engine.chapters(rule, detailPath: item.href)
        return list.map { Chapter(name: $0.name, href: $0.href) }
    }

    func resolve(_ chapter: Chapter) async throws -> PlaybackTarget {
        // 采集型的播放地址在详情页里，需要在页面里找 <video>/<source> 或播放器脚本
        guard let url = rule.absolute(chapter.href) else {
            throw RuleEngine.EngineError.badURL
        }
        // ① 先试 MacCMS 标准链路（纯 HTTP，覆盖面最大）
        do {
            let r = try await MacCMSResolver.resolve(playPage: url)
            return PlaybackTarget(url: r.url, headers: r.headers)
        } catch {
            // ② 退回：页面里直接有 m3u8/mp4
            let html = try await fetch(url)
            if let direct = extractVideoURL(from: html) {
                return PlaybackTarget(
                    url: direct,
                    headers: ["Referer": url.absoluteString, "User-Agent": ua]
                )
            }
            throw error
        }
    }

    private var ua: String {
        if let u = rule.userAgent, !u.isEmpty { return u }
        return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }

    private func fetch(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb)) ?? ""
    }

    /// 从详情页里找直链：m3u8 / mp4
    private func extractVideoURL(from html: String) -> URL? {
        let patterns = [
            #"https?://[^"'\s\\]+\.m3u8[^"'\s\\]*"#,
            #"https?://[^"'\s\\]+\.mp4[^"'\s\\]*"#,
            #"["'](https?:)?//[^"'\s]+\.m3u8[^"'\s]*["']"#
        ]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = html as NSString
            if let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
                var s = ns.substring(with: m.range)
                s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if s.hasPrefix("//") { s = "https:" + s }
                if let u = URL(string: s) { return u }
            }
        }
        return nil
    }
}
