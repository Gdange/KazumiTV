import Foundation

/// 通用数据源协议：所有内容来源都要实现这三个方法
///
/// 设计目标：一套 UI 接任意源
///   - XPathSource  → Kazumi 规则采集（几百个站点）
///   - WebDAVSource → NAS / AList
///   - APISource    → 平台官方接口（含 DRM）
protocol Source: Identifiable {
    var id: String { get }
    var name: String { get }
    var kind: SourceKind { get }

    /// 搜索
    func search(_ keyword: String) async throws -> [MediaItem]

    /// 取某部作品的章节/剧集列表
    func chapters(_ item: MediaItem) async throws -> [Chapter]

    /// 解析出可播放目标（URL + 请求头 + DRM 类型）
    func resolve(_ chapter: Chapter) async throws -> PlaybackTarget
}

enum SourceKind: String, Codable {
    case catalog     // 采集型：搜索 → 详情 → 剧集（Kazumi 规则）
    case library     // 本地库：NAS / WebDAV / Alist
    case streaming   // 流媒体平台：需要登录与 DRM
}

struct MediaItem: Identifiable, Hashable {
    var id: String { href }
    let name: String
    let href: String
    let poster: String?
    let sourceID: String

    init(name: String, href: String, poster: String? = nil, sourceID: String) {
        self.name = name
        self.href = href
        self.poster = poster
        self.sourceID = sourceID
    }
}

struct Chapter: Identifiable, Hashable {
    var id: String { href }
    let name: String
    let href: String
}

/// 播放目标：把"能不能播"和"怎么播"都表达清楚
struct PlaybackTarget {
    let url: URL
    var headers: [String: String] = [:]
    var drm: DRMKind = .none
}

enum DRMKind {
    case none
    case fairPlay(certificate: Data, licenseURL: URL)
    case unsupported(reason: String)
}

/// 数据源注册表
@MainActor
final class SourceRegistry: ObservableObject {
    @Published private(set) var sources: [any Source] = []

    func register(_ source: any Source) {
        guard !sources.contains(where: { $0.id == source.id }) else { return }
        sources.append(source)
    }

    func unregister(id: String) {
        sources.removeAll { $0.id == id }
    }

    func source(id: String) -> (any Source)? {
        sources.first { $0.id == id }
    }
}
