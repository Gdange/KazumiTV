import Foundation

/// 把一条 Kazumi 规则包装成通用 Source
struct XPathSource: Source {
    let rule: KazumiRule
    private let engine = RuleEngine()

    var id: String { "kazumi.\(rule.name)" }
    var name: String { rule.name }
    var kind: SourceKind { .catalog }

    /// 协议要求的方法：走完整降级
    func search(_ keyword: String) async throws -> [MediaItem] {
        try await search(keyword, fast: false)
    }

    func search(_ keyword: String, fast: Bool) async throws -> [MediaItem] {
        if let hit = await SearchCache.shared.get(source: id, keyword: keyword) { return hit }
        let r = try await _search(keyword, fast: fast)
        if !r.isEmpty { await SearchCache.shared.put(source: id, keyword: keyword, results: r) }
        return r
    }

    private func _search(_ keyword: String, fast: Bool) async throws -> [MediaItem] {
        // 采集站对带空格/副标题的长名字经常搜不到，逐级降级重试
        // fast=true 时只试第一个变体（多源并发扫描时用，避免请求爆炸）
        let all = Self.searchVariants(keyword)
        let variants = fast ? Array(all.prefix(1)) : all
        var lastError: Error?
        for v in variants {
            do {
                let r = try await engine.search(rule, keyword: v)
                if !r.isEmpty {
                    return r.map { it in
                        var p: String? = nil
                        if let raw = it.poster {
                            if raw.hasPrefix("//") { p = "https:" + raw }
                            else if raw.hasPrefix("http") { p = raw }
                            else if let u = rule.absolute(raw) { p = u.absoluteString }
                        }
                        return MediaItem(name: it.name, href: it.href, poster: p, sourceID: id)
                    }
                }
            } catch {
                lastError = error
            }
        }
        if let e = lastError { throw e }
        throw RuleEngine.EngineError.empty
    }

    /// 带别名扩展的关键词变体（详情页有 Bangumi 数据时用这个）
    static func searchVariants(_ keyword: String, aliases: [String] = []) -> [String] {
        var out = searchVariants(keyword)
        for a in aliases where !a.isEmpty && a.count > 1 {
            if !out.contains(a) { out.append(a) }
            // 别名去掉副标题
            if let r = a.range(of: "：") { out.append(String(a[..<r.lowerBound])) }
            if let r = a.range(of: ":") { out.append(String(a[..<r.lowerBound])) }
        }
        return out
    }

    /// 关键词变体：全名 → 去空格 → 第一段 → 前 6 字
    static func searchVariants(_ keyword: String) -> [String] {
        var out: [String] = []
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !out.contains(t) { out.append(t) }
        }
        add(keyword)
        add(keyword.replacingOccurrences(of: " ", with: ""))
        if let first = keyword.split(separator: " ").first, first.count >= 2 {
            add(String(first))
        }
        // 去掉常见的季数/剧场版后缀
        for suffix in [" 第", " 第二", " 第三", " 第四", " 剧场版", " 完结篇", " OVA", " TV"] {
            if let r = keyword.range(of: suffix) {
                add(String(keyword[..<r.lowerBound]))
            }
        }
        if keyword.count > 6 { add(String(keyword.prefix(6))) }
        return out
    }

    private func searchSingle(_ keyword: String) async throws -> [MediaItem] {
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

        // 同一个剧集在多个线路下会重复出现（「第1集」和「第01集」也算同一集），
        // 合并成一条，其余线路收进 alternatives
        var order: [String] = []
        var display: [String: String] = [:]
        var byKey: [String: [String]] = [:]

        for c in list {
            let raw = c.name.trimmingCharacters(in: .whitespaces)
            let key = Self.normalizeEpisode(raw)
            if byKey[key] == nil {
                order.append(key)
                display[key] = raw
            }
            byKey[key, default: []].append(c.href)
        }

        let merged = order.compactMap { k -> Chapter? in
            guard let hrefs = byKey[k], let first = hrefs.first else { return nil }
            return Chapter(name: display[k] ?? k, href: first, alternatives: Array(hrefs.dropFirst()))
        }
        NSLog("[KZ-CH] raw=\(list.count) merged=\(merged.count) alts=\(merged.first?.alternatives.count ?? 0)")
        return merged
    }

    /// 章节名归一化：「第01集」/「第1集」/「第01话」统一成同一个 key
    static func normalizeEpisode(_ name: String) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: " ", with: "")
        s = s.replacingOccurrences(of: "话", with: "集")
        s = s.replacingOccurrences(of: "話", with: "集")
        // 去掉数字前的多余 0：第01集 → 第1集
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "0", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex,
               s[next].isNumber, out.last?.isNumber != true {
                i = next
                continue
            }
            out.append(ch)
            i = s.index(after: i)
        }
        return out
    }

    func resolve(_ chapter: Chapter) async throws -> PlaybackTarget {
        // 同一集的多条线路**并行**试，谁先成功用谁。
        // 串行的话，第一条线路失败要等满超时（5s+5s+8s），用户得干等半分钟。
        let hrefs = chapter.allHrefs
        if hrefs.count == 1 {
            return try await resolveSingle(href: hrefs[0])
        }
        return try await withThrowingTaskGroup(of: PlaybackTarget?.self) { group in
            for href in hrefs {
                group.addTask {
                    do { return try await self.resolveSingle(href: href) }
                    catch {
                        NSLog("[KZ-RESOLVE] line failed: " + String(href.prefix(46)))
                        return nil
                    }
                }
            }
            for try await r in group {
                if let r { group.cancelAll(); return r }
            }
            throw RuleEngine.EngineError.empty
        }
    }

    private func resolveSingle(href: String) async throws -> PlaybackTarget {
        // 采集型的播放地址在详情页里，需要在页面里找 <video>/<source> 或播放器脚本
        guard let url = rule.absolute(href) else {
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
