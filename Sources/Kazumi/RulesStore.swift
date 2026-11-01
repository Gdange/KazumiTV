import Foundation

/// 内置规则仓库：从 bundle 的 rules/ 目录加载
enum RulesStore {

    static func loadBundled() -> [KazumiRule] {
        guard let dir = Bundle.main.url(forResource: "rules", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                      includingPropertiesForKeys: nil)
        else {
            return []
        }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> KazumiRule? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(KazumiRule.self, from: data)
            }
            .sorted { $0.name < $1.name }
    }
}
