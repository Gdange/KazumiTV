import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// 接管 AVPlayer 的网络请求
///
/// 为什么需要：AVPlayer 内部的 URL 加载走 Network.framework，
/// 在 fake-ip / 特殊证书场景下会直接返回 -1200，且没有任何 API 能放宽。
/// 改成自己用 URLSession 取数据（和 curl 同一套栈），再喂给播放器。
final class StreamLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let scheme = "kzstream"
    private let headers: [String: String]
    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private let lock = NSLock()

    init(headers: [String: String]) {
        self.headers = headers
        super.init()
    }

    /// 把真实 URL 换成自定义 scheme，AVPlayer 才会把请求交给我们
    /// 注意：只改 scheme，host/path/query 全部保留（包括 query 里的签名参数）
    static func disguised(_ url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = scheme
        guard let out = c?.url else { return url }
        NSLog("[KZ-LOAD] disguise %@ → %@", url.absoluteString, out.absoluteString)
        return out
    }

    static func real(_ url: URL) -> URL {
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = url.scheme == scheme ? "https" : url.scheme
        return c?.url ?? url
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {

        guard var comps = URLComponents(url: request.request.url ?? URL(string: "https://x")!, resolvingAgainstBaseURL: false) else {
            return false
        }
        comps.scheme = "https"
        guard let realURL = comps.url else { return false }

        var req = URLRequest(url: realURL)
        req.timeoutInterval = 20
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        NSLog("[KZ-LOAD] → %@", realURL.absoluteString)
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            defer { self?.forget(request) }

            if let error {
                NSLog("[KZ-LOAD] ✗ %@ : %@", realURL.lastPathComponent, error.localizedDescription)
                request.finishLoading(with: error)
                return
            }
            if let http = response as? HTTPURLResponse {
                NSLog("[KZ-LOAD] ← %d %d B %@", http.statusCode, data?.count ?? 0, realURL.lastPathComponent)
            }
            guard let http = response as? HTTPURLResponse, let data else {
                request.finishLoading(with: NSError(domain: "kz", code: -1,
                                                    userInfo: [NSLocalizedDescriptionKey: "无响应"]))
                return
            }

            // 填内容信息：类型透传服务端，长度用本次拿到的完整字节数
            if let info = request.contentInformationRequest {
                // 关掉 Range：我们每次都是整包返回，告诉播放器支持 Range 会让它
                // 按区间反复请求，字节对不上就报 CoreMediaErrorDomain -12881
                info.isByteRangeAccessSupported = false
                info.contentLength = Int64(data.count)

                let ct = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if ct.contains("mpegurl") {
                    info.contentType = "public.m3u8"
                } else if ct.contains("mp2t") || realURL.pathExtension == "ts" {
                    info.contentType = "public.mpeg-2-transport-stream"
                } else if ct.contains("mp4") || realURL.pathExtension == "mp4" {
                    info.contentType = "public.mpeg-4"
                } else if let v = http.value(forHTTPHeaderField: "Content-Type"), !v.isEmpty {
                    info.contentType = v
                }
            }

            // 填数据：**整包返回**。我们不向上游转发 Range，所以交给播放器的就是完整内容，
            // 若按 requestedOffset 切片会导致多轮 Range 请求拼接错乱（-12881）。
            if let dr = request.dataRequest {
                dr.respond(with: data)
            }
            request.finishLoading()
        }

        lock.lock()
        tasks[ObjectIdentifier(request)] = task
        lock.unlock()
        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        lock.lock()
        tasks[ObjectIdentifier(loadingRequest)]?.cancel()
        tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))
        lock.unlock()
    }

    private func forget(_ r: AVAssetResourceLoadingRequest) {
        lock.lock()
        tasks.removeValue(forKey: ObjectIdentifier(r))
        lock.unlock()
    }
}
