import Foundation

/// 官方规则仓库条目（对齐 KazumiRules/index.json）
struct CatalogItem: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let version: String?
    let useNativePlayer: Bool?
    let antiCrawlerEnabled: Bool?
    let author: String?
    let lastUpdate: Int64?      // 毫秒时间戳
}

/// 已安装规则（bundle 内置 + 用户导入）
struct InstalledRule: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let version: String?
    let rule: KazumiRule
    let isBuiltin: Bool
}

/// 规则目录服务：完全对齐官方接口
///   列表  {repo}/index.json
///   单条  {repo}/{name}.json
enum RuleCatalog {

    /// 官方源 + 镜像（国内直连 raw.githubusercontent 常失败）
    static var sources: [String] {
        [
            "https://raw.githubusercontent.com/Predidit/KazumiRules/main/",
            "https://ghfast.top/https://raw.githubusercontent.com/Predidit/KazumiRules/main/",
            "https://gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/"
        ]
    }

    private static let ua = "KazumiTV/0.1 (tvOS)"

    // MARK: - 网络

    private static func fetchText(_ url: String) async throws -> String {
        guard let u = URL(string: url) else { throw Err.badURL }
        var req = URLRequest(url: u)
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Err.http(http.statusCode)
        }
        guard let s = String(data: data, encoding: .utf8) else { throw Err.decode }
        return s
    }

    /// 依次尝试官方源与镜像
    private static func fetchWithFallback(_ path: String) async throws -> String {
        var lastError: Error = Err.network
        for base in sources {
            do { return try await fetchText(base + path) }
            catch { lastError = error; continue }
        }
        throw lastError
    }

    /// 拉取规则目录
    static func list() async throws -> [CatalogItem] {
        let raw = try await fetchWithFallback("index.json")
        guard let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([CatalogItem].self, from: data)
        else { throw Err.decode }
        return list.sorted { $0.name < $1.name }
    }

    /// 拉取单条规则
    static func download(_ name: String) async throws -> KazumiRule {
        let raw = try await fetchWithFallback("\(name).json")
        guard let data = raw.data(using: .utf8),
              let rule = try? JSONDecoder().decode(KazumiRule.self, from: data)
        else { throw Err.decode }
        return rule
    }

    // MARK: - 本地存储

    static var userRulesDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("rules", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveUserRule(_ rule: KazumiRule, raw json: Data? = nil) throws {
        let url = userRulesDir.appendingPathComponent("\(rule.name).json")
        let data = try json ?? JSONEncoder().encode(rule)
        try data.write(to: url)
    }

    static func deleteUserRule(_ name: String) {
        let url = userRulesDir.appendingPathComponent("\(name).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// 已安装 = bundle 内置 + 用户目录
    static func installed() -> [InstalledRule] {
        var out: [InstalledRule] = []

        for r in RulesStore.loadBundled() {
            out.append(InstalledRule(name: r.name, version: r.version, rule: r, isBuiltin: true))
        }

        let files = (try? FileManager.default.contentsOfDirectory(at: userRulesDir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let r = try? JSONDecoder().decode(KazumiRule.self, from: data) else { continue }
            if let i = out.firstIndex(where: { $0.name == r.name }) {
                out[i] = InstalledRule(name: r.name, version: r.version, rule: r, isBuiltin: false)
            } else {
                out.append(InstalledRule(name: r.name, version: r.version, rule: r, isBuiltin: false))
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    enum Err: LocalizedError {
        case badURL, decode, network, http(Int)
        var errorDescription: String? {
            switch self {
            case .badURL: return "地址无效"
            case .decode: return "返回内容不是有效的规则 JSON"
            case .network: return "所有源都连不上（含镜像）"
            case .http(let c): return "站点返回 HTTP \(c)"
            }
        }
    }
}
