import Foundation
import SwiftUI
import AVFoundation

/// 自动化测试入口：启动时读 UserDefaults，自动走一遍「搜索 → 选源 → 解析 → 播放」
/// 用法：xcrun simctl spawn <dev> defaults write com.yg.qytv kzAutoPlay "AGE|番名"
enum DebugAutoPlay {
    static var request: (source: String, name: String)? {
        guard let raw = UserDefaults.standard.string(forKey: "kzAutoPlay"), !raw.isEmpty else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: "kzAutoPlay") }
}

struct AutoPlayRunner: View {
    var body: some View {
        Color.clear.task {
            guard let req = DebugAutoPlay.request else { return }
            NSLog("[KZ-AUTO] start source=\(req.source) name=\(req.name)")
            await run(source: req.source, name: req.name)
        }
    }

    private func run(source: String, name: String) async {
        guard let rule = RuleCatalog.installed().first(where: { $0.rule.name == source })?.rule else {
            NSLog("[KZ-AUTO] rule not found")
            return
        }
        let src = XPathSource(rule: rule)

        guard let list = try? await src.search(name), let item = list.first else {
            NSLog("[KZ-AUTO] search failed"); return
        }
        NSLog("[KZ-AUTO] found: \(item.name)")

        guard let chapters = try? await src.chapters(item), let ch = chapters.first else {
            NSLog("[KZ-AUTO] chapters failed"); return
        }
        NSLog("[KZ-AUTO] chapters=\(chapters.count) first=\(ch.name) alts=\(ch.alternatives.count)")

        let t0 = Date()
        do {
            let target = try await src.resolve(ch)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            NSLog("[KZ-AUTO] ✅ resolved in \(ms)ms → \(target.url.absoluteString)")
            await verifyPlayback(target)
        } catch {
            NSLog("[KZ-AUTO] ❌ resolve failed: \(error.localizedDescription)")
        }
        DebugAutoPlay.clear()
    }

    private func verifyPlayback(_ target: PlaybackTarget) async {
        // 方案 A：直接给 AVPlayer 真地址（最简单，能用就用）
        if await tryDirect(target) { return }
        // 方案 B：用 StreamLoader 接管（应对 TLS 受限的 CDN）
        await tryLoader(target)
    }

    private func tryDirect(_ target: PlaybackTarget) async -> Bool {
        let asset = AVURLAsset(url: target.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": target.headers
        ])
        return await play(asset: asset, tag: "direct")
    }

    private func tryLoader(_ target: PlaybackTarget) async -> Bool {
        let disguised = StreamLoader.disguised(target.url)
        let asset = AVURLAsset(url: disguised)
        let loader = StreamLoader(headers: target.headers)
        asset.resourceLoader.setDelegate(loader, queue: DispatchQueue(label: "kz.auto"))
        return await play(asset: asset, tag: "loader")
    }

    private func play(asset: AVURLAsset, tag: String) async -> Bool {
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        do {
            let playable = try await asset.load(.isPlayable)
            let dur = try await asset.load(.duration)
            NSLog("[KZ-AUTO][\(tag)] playable=\(playable) dur=\(dur.seconds)s")
            guard playable else { return false }

            player.play()
            try await Task.sleep(nanoseconds: 6_000_000_000)
            let t = player.currentTime().seconds
            let ok = t > 0.5
            NSLog("[KZ-AUTO][\(tag)] ▶ \(ok ? "OK" : "FAIL") t=\(String(format: "%.2f", t))s status=\(item.status.rawValue) err=\(item.error?.localizedDescription ?? "none")")
            return ok
        } catch {
            NSLog("[KZ-AUTO][\(tag)] ❌ \(error.localizedDescription)")
            return false
        }
    }
}
