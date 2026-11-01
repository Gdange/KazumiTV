import AVFoundation
import Foundation

/// FairPlay Streaming 最小实现：
/// 证书加载 → AVContentKeySession → 拦截 skd:// → 生成 SPC → 请求 CKC → 播放
final class FairPlayManager: NSObject {

    struct Config {
        var certificate: Data          // fairplay.cer 的 DER
        var licenseURL: URL            // 例如 https://drml-video.iq.com/...
        var assetID: String            // 内容标识，从 m3u8 的 EXT-X-KEY URI 里取
        var headers: [String: String] = [:]
        var bodyBuilder: (Data) -> Data = { $0 }   // 把 SPC 包成服务端要的格式
    }

    private let config: Config
    private let session: AVContentKeySession
    private let loader = AssetLoaderDelegate()
    let player: AVPlayer

    private init(config: Config, url: URL) {
        self.config = config
        self.session = AVContentKeySession(keySystem: .fairPlayStreaming)

        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(loader, queue: .global())
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))

        super.init()
        session.setDelegate(self, queue: .global())
        session.addContentKeyRecipient(asset)
        loader.onKeyURI = { [weak self] uri in
            self?.assetIDFromKeyURI = uri
        }
    }

    private var assetIDFromKeyURI: String?

    static func make(from url: URL) throws -> FairPlayManager {
        guard let certURL = Bundle.main.url(forResource: "fairplay", withExtension: "cer"),
              let cert = try? Data(contentsOf: certURL) else {
            throw NSError(domain: "FPS", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "缺少 fairplay.cer（放进 target 的 Copy Bundle Resources）"])
        }
        // TODO: 换成真实 license 地址；先用占位，跑通后再填
        let license = URL(string: "https://drml-video.iq.com/license")!
        let cfg = Config(certificate: cert, licenseURL: license, assetID: "")
        return FairPlayManager(config: cfg, url: url)
    }
}

extension FairPlayManager: AVContentKeySessionDelegate {

    func contentKeySession(_ session: AVContentKeySession,
                           didProvide keyRequest: AVContentKeyRequest) {
        let assetID = assetIDFromKeyURI ?? config.assetID
        guard !assetID.isEmpty else {
            keyRequest.processContentKeyResponseError(
                NSError(domain: "FPS", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "拿不到 assetID（EXT-X-KEY URI 为空）"]))
            return
        }

        keyRequest.makeStreamingContentKeyRequestData(
            forApp: config.certificate,
            contentIdentifier: Data(assetID.utf8),
            options: nil
        ) { [weak self] spc, error in
            guard let self else { return }
            if let error {
                keyRequest.processContentKeyResponseError(error)
                return
            }
            guard let spc else { return }

            var req = URLRequest(url: self.config.licenseURL)
            req.httpMethod = "POST"
            req.httpBody = self.config.bodyBuilder(spc)
            self.config.headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }

            URLSession.shared.dataTask(with: req) { ckc, _, err in
                if let err {
                    keyRequest.processContentKeyResponseError(err)
                    return
                }
                guard let ckc else { return }
                let response = AVContentKeyResponse(fairPlayStreamingKeyResponseData: ckc)
                keyRequest.processContentKeyResponse(response)
            }.resume()
        }
    }
}

/// 拦截 skd:// 请求，把 URI 交给 FairPlayManager
final class AssetLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    var onKeyURI: ((String) -> Void)?

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = request.request.url, url.scheme == "skd" else { return false }
        onKeyURI?(url.absoluteString)
        return true
    }
}
