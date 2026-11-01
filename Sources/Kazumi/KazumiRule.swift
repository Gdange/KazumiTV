import Foundation

/// 一条 Kazumi 采集规则（对齐 KazumiRules 仓库的 JSON 结构）
struct KazumiRule: Codable, Identifiable, Hashable {
    var id: String { name }

    var name: String
    var version: String?
    var api: String?
    var type: String?
    var baseURL: String
    var searchURL: String
    var userAgent: String?

    // 六个 XPath 选择器
    var searchList: String
    var searchName: String
    var searchResult: String
    var chapterRoads: String
    var chapterResult: String

    var muliSources: Bool?
    var useWebview: Bool?
    var useNativePlayer: Bool?
    var deprecated: Bool?

    enum CodingKeys: String, CodingKey {
        case name, version, api, type, baseURL, searchURL, userAgent
        case searchList, searchName, searchResult, chapterRoads, chapterResult
        case muliSources, useWebview, useNativePlayer, deprecated
    }
}

/// 搜索结果条目
struct RuleSearchItem: Identifiable, Hashable {
    var id: String { href }
    let name: String
    let href: String
    var poster: String? = nil
}

/// 章节条目
struct RuleChapter: Identifiable, Hashable {
    var id: String { href }
    let name: String
    let href: String
}

extension KazumiRule {
    /// 构造搜索请求 URL：规则里用 @keyword 占位
    func searchURL(for keyword: String) -> URL? {
        // urlQueryAllowed 会放行 # & = 等字符，其中 # 会被当作锚点把搜索词截断，
        // & 会被当作参数分隔符。逐个剔除后再编码。
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "#&=?+/:%[]@!$'()*,")
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: cs) ?? keyword
        let s = searchURL.replacingOccurrences(of: "@keyword", with: encoded)
        return URL(string: s)
    }

    /// 相对路径补全成绝对地址
    func absolute(_ href: String) -> URL? {
        if href.hasPrefix("http") { return URL(string: href) }
        var base = baseURL
        if !base.hasSuffix("/") { base += "/" }
        let path = href.hasPrefix("/") ? String(href.dropFirst()) : href
        return URL(string: base + path)
    }
}
