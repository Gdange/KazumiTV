import Foundation

/// 规则执行器：拿规则去打站点，解析出搜索结果与章节
struct RuleEngine {

    enum EngineError: LocalizedError {
        case badURL, http(Int), empty, parse(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "规则里的地址无效"
            case .http(let c): return "站点返回 HTTP \(c)"
            case .empty: return "页面解析结果为空"
            case .parse(let m): return "解析失败：\(m)"
            }
        }
    }

    private func fetch(_ url: URL, ua: String?) async throws -> String {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        if let ua, !ua.isEmpty {
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
        } else {
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw EngineError.http(http.statusCode)
        }
        // 站点编码常不是 UTF-8，先按 UTF-8 试，失败退回 GB18030
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb)) ?? ""
    }

    /// 搜索：返回条目（名称 + 详情链接）
    func search(_ rule: KazumiRule, keyword: String) async throws -> [RuleSearchItem] {
        guard let url = rule.searchURL(for: keyword) else { throw EngineError.badURL }
        NSLog("[KZ-SEARCH] keyword=%@ url=%@", keyword, url.absoluteString)
        let html = try await fetch(url, ua: rule.userAgent)
        NSLog("[KZ-SEARCH] htmlBytes=%d", html.count)

        // 调试：落一份到 Documents，模拟器里可以直接看
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? html.write(to: dir.appendingPathComponent("last_search.html"),
                            atomically: true, encoding: .utf8)
        }

        guard let doc = XPathDoc(html: html) else {
            throw EngineError.parse("HTML 解析失败，长度 \(html.count)")
        }

        let rows = doc.query(rule.searchList)
        if rows.isEmpty {
            throw EngineError.parse("列表 XPath 零命中（HTML \(html.count) 字节）")
        }

        // Kazumi 的语义：名称与链接都在「每一行」内部查找
        var items: [RuleSearchItem] = []
        for row in rows {
            let nameHit = doc.query(in: row.node, rule.searchName).first
            let linkHit = doc.query(in: row.node, rule.searchResult).first
            let name = nameHit?.text ?? ""
            let href = linkHit?.href ?? ""
            guard !name.isEmpty, !href.isEmpty else { continue }

            // 海报：行内第一张图，常见懒加载属性都认
            var poster: String? = nil
            for img in doc.query(in: row.node, "//img") {
                if let s = img.src, !s.isEmpty { poster = s; break }
            }
            items.append(RuleSearchItem(name: name, href: href, poster: poster))
        }
        if items.isEmpty { throw EngineError.parse("行内没解析出条目（行数 \(rows.count)）") }
        return items
    }

    /// 详情页：返回章节列表
    func chapters(_ rule: KazumiRule, detailPath: String) async throws -> [RuleChapter] {
        guard let url = rule.absolute(detailPath) else { throw EngineError.badURL }
        let html = try await fetch(url, ua: rule.userAgent)
        guard let doc = XPathDoc(html: html) else { throw EngineError.empty }

        // 章节同理：先找容器，再在容器内找条目
        let roads = doc.query(rule.chapterRoads)
        var out: [RuleChapter] = []

        if roads.isEmpty {
            // 有些站点没有独立容器，退回全局
            for (i, n) in doc.query(rule.chapterResult).enumerated() {
                guard let href = n.href, !href.isEmpty else { continue }
                let name = n.text.isEmpty ? "第 \(i + 1) 集" : n.text
                out.append(RuleChapter(name: name, href: href))
            }
        } else {
            // 多个容器 = 多条线路：全部收下，交给上层按剧集名合并成「一集多线路」
            for road in roads {
                for n in doc.query(in: road.node, rule.chapterResult) {
                    guard let href = n.href, !href.isEmpty else { continue }
                    let name = n.text.isEmpty ? "第 \(out.count + 1) 集" : n.text
                    out.append(RuleChapter(name: name, href: href))
                }
            }
        }

        if out.isEmpty { throw EngineError.parse("章节解析为空（容器 \(roads.count) 个）") }

        // 多线路会重复：先按链接去重，再按名称去重（同名只留第一集）
        var seenHref = Set<String>()
        var seenName = Set<String>()
        let unique = out.filter { c in
            guard seenHref.insert(c.href).inserted else { return false }
            return seenName.insert(c.name).inserted
        }
        return unique
    }
}
