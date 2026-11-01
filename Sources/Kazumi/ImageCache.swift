import SwiftUI
import UIKit

/// 带内存 + 磁盘缓存的图片组件
/// - 优先命中内存缓存（滚动不重复解码）
/// - 其次走 URLCache（已下载的图不再发请求）
/// - 失败自动重试 2 次，仍失败才显示占位
struct CachedImage: View {
    let url: URL?
    var placeholder: String = ""
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false
    @State private var loading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                fallback
            } else {
                Rectangle()
                    .fill(KZ.card.opacity(0.6))
                    .overlay(
                        ProgressView().scaleEffect(0.7).opacity(loading ? 1 : 0)
                    )
            }
        }
        .task(id: url) { await load() }
    }

    private var fallback: some View {
        Rectangle()
            .fill(KZ.card)
            .overlay(
                Text(placeholder.prefix(1))
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(KZ.dim)
            )
    }

    private func load() async {
        guard let url else { failed = true; return }

        if let hit = ImageMemoryCache.shared.get(url) {
            image = hit
            return
        }

        loading = true
        defer { loading = false }

        for attempt in 0..<3 {
            do {
                var req = URLRequest(url: url)
                req.timeoutInterval = 15
                // 允许使用缓存
                req.cachePolicy = attempt == 0 ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData
                let (data, _) = try await URLSession.shared.data(for: req)
                if let img = UIImage(data: data) {
                    ImageMemoryCache.shared.set(url, img)
                    await MainActor.run { image = img }
                    return
                }
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(300_000_000 * (attempt + 1)))
                }
            }
        }
        await MainActor.run { failed = true }
    }
}

/// 内存图片缓存（NSCache 自动响应内存压力）
final class ImageMemoryCache {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 80 * 1024 * 1024   // 80 MB
    }

    func get(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func set(_ url: URL, _ img: UIImage) {
        let cost = Int(img.size.width * img.size.height * 4)
        cache.setObject(img, forKey: url as NSURL, cost: cost)
    }
}

/// 图片预取：列表出来后后台把封面抓进缓存，滚动时直接命中
enum ImagePrefetcher {
    /// 全局闸门：同一时刻只允许一个预取任务在跑，避免叠加上量
    private static var busy = false
    /// 播放期间暂停预取，把带宽让给视频
    private static var paused = false

    static func pause() { paused = true }
    static func resume() { paused = false }
    /// 本进程已预取过的 URL，避免重复排队
    private static var seen = Set<String>()

    /// - Parameters:
    ///   - limit: 最多预取多少张（默认 24，约一屏）
    ///   - concurrency: 并发数（默认 3，留带宽给播放）
    static func prefetch(_ urls: [String], limit: Int = 24, concurrency: Int = 3) {
        guard !busy, !paused else { return }             // 播放中 / 上一轮未完成都不启动
        let fresh = urls.filter { !$0.isEmpty && !seen.contains($0) }
        let targets = Array(fresh.prefix(limit)).compactMap { URL(string: $0) }
        guard !targets.isEmpty else { return }
        targets.forEach { seen.insert($0.absoluteString) }

        busy = true
        Task.detached(priority: .utility) {
            defer { busy = false }
            var index = 0
            while index < targets.count {
                if paused { return }                      // 播放开始了，立刻收手
                let batch = Array(targets[index..<min(index + concurrency, targets.count)])
                index += concurrency
                await withTaskGroup(of: Void.self) { group in
                    for u in batch {
                        group.addTask { await fetchOne(u) }
                    }
                }
                // 批次之间喘口气，别把带宽打满
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private static func fetchOne(_ url: URL) async {
        if ImageMemoryCache.shared.get(url) != nil { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = UIImage(data: data) else { return }
        ImageMemoryCache.shared.set(url, img)
    }
}
