import Foundation

/// 多源匹配（对齐官方 Kazumi 的「播放来源」模型）
///
/// 核心差异：不是「找到一个就停」，而是**并行问完所有源并记录各自状态**：
///   - 有结果（带条数和条目）
///   - 需要验证（Cloudflare / 人机校验）
///   - 检索失败（站点挂、规则过期）
///   - 超时
/// 结果边扫边发布，UI 可以增量显示。
@MainActor
final class SourceMatcher: ObservableObject {

    enum State: Equatable {
        case pending
        case results([MediaItem])
        case needsVerify
        case failed(String)
    }

    /// 可播放性：搜到 ≠ 能播，只有解析出真实地址才算
    enum Playable: Equatable {
        case checking
        case yes
        case no(String)      // 不能播的原因
    }

    struct Entry: Identifiable {
        let id: String
        let rule: KazumiRule
        var state: State
        var playable: Playable = .checking

        var count: Int {
            if case .results(let r) = state { return r.count }
            return 0
        }
        /// 只有真正能解析出地址的，才算可用
        var usable: Bool { playable == .yes }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var scanning = false
    @Published private(set) var finished = false

    /// 单源超时
    private let perSource: Double = 5
    /// 并发数
    private let concurrency = 15
    /// 同一部番的扫描结果缓存 10 分钟，避免反复重扫
    private var cache: [String: (entries: [Entry], at: Date)] = [:]

    var totalResults: Int { entries.reduce(0) { $0 + $1.count } }
    var usableCount: Int { entries.filter { $0.count > 0 }.count }

    func scan(name: String, aliases: [String] = []) async {
        // 命中缓存直接返回，不再重复扫
        if let c = cache[name], Date().timeIntervalSince(c.at) < 600, !c.entries.isEmpty {
            entries = c.entries
            finished = true
            return
        }
        guard !scanning else { return }
        scanning = true
        finished = false
        defer { scanning = false; finished = true }

        // 跳过长期失败的源，减少无效请求
        let rules = RuleCatalog.installed().map(\.rule)
            .filter { SourceRank.score($0.name) > -6 }
            .sorted { SourceRank.score($0.name) > SourceRank.score($1.name) }

        entries = rules.map { Entry(id: $0.name, rule: $0, state: .pending) }
        let indexOf = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
        let timeout = perSource

        await withTaskGroup(of: (String, State).self) { group in
            var queue = rules[...]
            var running = 0

            // 先填满并发
            while running < concurrency, let rule = queue.first {
                queue = queue.dropFirst()
                running += 1
                group.addTask { (rule.name, await Self.probe(rule: rule, name: name, aliases: aliases, timeout: timeout)) }
            }

            // 完成一个补一个
            for await (sourceID, state) in group {
                running -= 1
                if let i = indexOf[sourceID] {
                    entries[i].state = state
                    if case .results = state { SourceRank.recordSuccess(sourceID) }
                    if case .failed = state { SourceRank.recordFailure(sourceID) }
                }
                if let rule = queue.first {
                    queue = queue.dropFirst()
                    running += 1
                    group.addTask { (rule.name, await Self.probe(rule: rule, name: name, timeout: 5)) }
                }
            }
        }

        // 对有结果的源逐个验证：能不能真的解析出播放地址
        await verifyPlayable()

        // 写缓存
        cache[name] = (entries, Date())
    }

    /// 验证哪些源真的能解析出播放地址
    private func verifyPlayable() async {
        let targets = entries.indices.filter {
            if case .results = entries[$0].state { return true }
            return false
        }
        guard !targets.isEmpty else { return }

        let snapshot = entries
        await withTaskGroup(of: (Int, Playable).self) { group in
            for i in targets {
                let entry = snapshot[i]
                group.addTask {
                    guard case .results(let list) = entry.state, let first = list.first else {
                        return (i, .no("没有条目"))
                    }
                    let src = XPathSource(rule: entry.rule)
                    guard let chapters = try? await src.chapters(first), let ch = chapters.first else {
                        return (i, .no("读取剧集失败"))
                    }
                    do {
                        _ = try await src.resolve(ch)
                        NSLog("[KZ-PLAY] %@ OK", entry.id)
                        return (i, .yes)
                    } catch {
                        let m = error.localizedDescription
                        NSLog("[KZ-PLAY] %@ FAIL: %@", entry.id, m)
                        // 把真实原因显示出来，别一律「解析不出地址」
                        return (i, .no(String(m.prefix(16))))
                    }
                }
            }
            for await (i, p) in group {
                entries[i].playable = p
            }
        }
    }

    /// 单源探测：区分「没搜到」「需要验证」「请求失败」
    nonisolated private static func probe(rule: KazumiRule, name: String, aliases: [String] = [], timeout: Double) async -> State {
        let src = XPathSource(rule: rule)
        let variants = Array(XPathSource.searchVariants(name, aliases: aliases).prefix(3))

        for v in variants {
            do {
                let list = try await withThrowingTaskGroup(of: [MediaItem].self) { group -> [MediaItem] in
                    group.addTask { try await src.search(v, fast: true) }
                    group.addTask {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        throw CancellationError()
                    }
                    let r = try await group.next() ?? []
                    group.cancelAll()
                    return r
                }
                if !list.isEmpty { return .results(list) }
            } catch is CancellationError {
                return .failed("超时")
            } catch let RuleEngine.EngineError.http(code) where code == 403 || code == 503 {
                return .needsVerify
            } catch {
                let m = error.localizedDescription
                if m.contains("验证") || m.contains("Cloudflare") || m.contains("challenge") {
                    return .needsVerify
                }
                continue
            }
        }
        return .failed("没搜到")
    }
}

/// 源的历史成功率
enum SourceRank {
    private static let key = "kz.sourceRank"

    static func score(_ name: String) -> Int {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int])?[name] ?? 0
    }

    static func recordSuccess(_ name: String) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
        d[name] = min((d[name] ?? 0) + 1, 99)
        UserDefaults.standard.set(d, forKey: key)
    }

    static func recordFailure(_ name: String) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
        d[name] = max((d[name] ?? 0) - 1, -20)
        UserDefaults.standard.set(d, forKey: key)
    }
}
