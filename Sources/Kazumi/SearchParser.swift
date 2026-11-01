import Foundation

/// 官方搜索语法解析器（对齐 lib/utils/search_parser.dart）
/// 支持：id: / tag: / sort: / season: / date:a..b / rank:a..b / score:a..b / weekday: / nsfw:
struct SearchQuery {
    var keyword = ""
    var id: Int?
    var tags: [String] = []
    var sort = "match"          // match / heat / rank / score
    var season: String?         // 2024Q4
    var dateRange: (String, String)?
    var rankRange: (Int, Int)?
    var scoreRange: (Double, Double)?
    var weekdays: [Int] = []
    var nsfw = false
}

enum SearchParser {

    private static let fieldNames = ["id", "tag", "sort", "season", "date",
                                     "rank", "score", "weekday", "nsfw"]

    static func parse(_ raw: String) -> SearchQuery {
        var q = SearchQuery()
        var rest = raw

        // id:
        if let m = firstMatch(#"id:(\d+)"#, in: raw), let id = Int(m) {
            q.id = id
            rest = rest.replacingOccurrences(of: "id:\(m)", with: " ")
        }

        // tag:（可多个）
        for t in allMatches(#"(?:^|\s)tag:([^\s]+)"#, in: raw) {
            let cleaned = t.replacingOccurrences(
                of: #"(?:id|tag|sort|season|date|rank|score|weekday|nsfw):.*$"#,
                with: "", options: .regularExpression)
            if !cleaned.isEmpty { q.tags.append(cleaned) }
            rest = rest.replacingOccurrences(of: "tag:\(t)", with: " ")
        }

        // sort:
        if let s = firstMatch(#"sort:([\w\-]+)"#, in: raw) {
            q.sort = s
            rest = rest.replacingOccurrences(of: "sort:\(s)", with: " ")
        }

        // season:
        if let s = firstMatch(#"season:(\d{4}Q[1-4])"#, in: raw) {
            q.season = s
            rest = rest.replacingOccurrences(of: "season:\(s)", with: " ")
        }

        // date:a..b
        if let m = firstMatch(#"date:(\d{4}-\d{2}-\d{2})\.\.(\d{4}-\d{2}-\d{2})"#, in: raw),
           let pair = parsePair(m) as? (String, String) {
            q.dateRange = pair
            rest = rest.replacingOccurrences(of: "date:\(m)", with: " ")
        }

        // rank:a..b
        if let m = firstMatch(#"rank:(\d*)\.\.(\d*)"#, in: raw) {
            let parts = m.split(separator: ".", omittingEmptySubsequences: true)
            let lo = Int(parts.first ?? "") ?? 1
            let hi = parts.count > 1 ? (Int(parts[1]) ?? 99999) : 99999
            q.rankRange = (lo, hi)
            rest = rest.replacingOccurrences(of: "rank:\(m)", with: " ")
        }

        // score:a..b
        if let m = firstMatch(#"score:(\d+(?:\.\d+)?)?\.\.(\d+(?:\.\d+)?)?"#, in: raw) {
            let parts = m.components(separatedBy: "..")
            let lo = Double(parts.first ?? "") ?? 0
            let hi = parts.count > 1 ? (Double(parts[1]) ?? 10) : 10
            q.scoreRange = (lo, hi)
            rest = rest.replacingOccurrences(of: "score:\(m)", with: " ")
        }

        // weekday:1,3,5
        if let m = firstMatch(#"weekday:([1-7](?:,[1-7])*)"#, in: raw) {
            q.weekdays = m.split(separator: ",").compactMap { Int($0) }
            rest = rest.replacingOccurrences(of: "weekday:\(m)", with: " ")
        }

        // nsfw:
        if raw.contains("nsfw:true") { q.nsfw = true }

        q.keyword = rest
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return q
    }

    // MARK: 工具
    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
            return ns.substring(with: m.range(at: 1))
        }
        return ns.substring(with: m.range)
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound
                ? ns.substring(with: m.range(at: 1)) : nil
        }
    }

    private static func parsePair(_ raw: String) -> Any? {
        let parts = raw.components(separatedBy: "..")
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}
