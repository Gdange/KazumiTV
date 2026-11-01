import SwiftUI
import AVKit

/// 播放页：AVPlayer + 实时画质信息
struct PlayScreen: View {
    let target: PlaybackTarget
    let title: String

    /// 同一部番的所有剧集（用于播放中切集）
    var chapters: [Chapter] = []
    /// Bangumi 官方剧集（显示正式标题）
    var bgmEpisodes: [BangumiEpisode] = []
    /// 当前是第几集
    var currentIndex: Int = 0
    /// 切集回调
    var onPick: ((Chapter) -> Void)? = nil

    @State private var showEpisodes = false
    @State private var showSpeed = false
    @State private var showTimer = false
    @State private var showInfo2 = false
    @State private var rate: Float = 1.0
    @State private var sleepMinutes: Int? = nil
    @State private var sleepDeadline: Date? = nil
    @State private var sleepRemaining: Int = 0

    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var resolution = "—"
    @State private var bitrate = "—"
    @State private var hdr = ""
    @State private var showInfo = true

    @State private var sizeObserver: NSKeyValueObservation?
    @State private var logObserver: NSObjectProtocol?
    @State private var loader: StreamLoader?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let error {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 52)).foregroundStyle(.orange)
                    Text(error).font(.system(size: 20)).multilineTextAlignment(.center)
                }.padding(60)
            } else if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                ProgressView("正在解析地址…")
            }

            VStack(alignment: .trailing, spacing: 10) {
                if showInfo && error == nil { infoBadge }

                HStack(spacing: 8) {
                    // 视频详情
                    Button { showInfo2 = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // 倍速
                    Button { showSpeed = true } label: {
                        Text(rate == 1.0 ? "倍速" : String(format: "%.2gx", rate))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // 定时关闭
                    Button { showTimer = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "moon.zzz")
                            if let m = sleepMinutes {
                                Text(sleepRemaining > 0 ? "\(sleepRemaining/60)m" : "\(m)m")
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    // 选集
                    if !chapters.isEmpty {
                        Button { showEpisodes = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet")
                                Text("\(currentIndex + 1)/\(chapters.count)")
                                    .font(.system(size: 13, design: .monospaced))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showInfo2) {
            VideoInfoSheet(item: player?.currentItem)
        }
        .sheet(isPresented: $showSpeed) {
            SpeedSheet(rate: $rate) { r in
                rate = r
                player?.rate = r
                showSpeed = false
            }
        }
        .sheet(isPresented: $showTimer) {
            SleepTimerSheet(current: sleepMinutes) { mins in
                showTimer = false
                applySleepTimer(mins)
            }
        }
        .sheet(isPresented: $showEpisodes) {
            EpisodePicker(chapters: chapters, current: currentIndex, bgmEpisodes: bgmEpisodes) { ch in
                showEpisodes = false
                onPick?(ch)
            }
        }
        .navigationTitle(title)
        .onAppear {
            ImagePrefetcher.pause()      // 播放优先，暂停后台图片预取
            start()
        }
        .onDisappear {
            ImagePrefetcher.resume()
            stop()
        }
    }

    /// 右上角画质角标
    private var infoBadge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Text(resolution)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                if !hdr.isEmpty {
                    Text(hdr)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(KZ.accent.opacity(0.9))
                        .foregroundStyle(KZ.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            Text("\(bitrate) Mbps")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(KZ.dim)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func start() {
        switch target.drm {
        case .unsupported(let reason):
            error = reason
            return
        case .fairPlay:
            error = "FairPlay 流需要额外实现（当前版本只支持明文）"
            return
        case .none:
            break
        }

        // 优先直连：绝大多数 CDN 用 header 就能播（实测可行）
        // 只有直连失败（TLS 受限的 CDN）才退回 StreamLoader
        let asset = AVURLAsset(url: target.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": target.headers
        ])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        player = p
        p.play()

        // 分辨率：KVO
        sizeObserver = item.observe(\.presentationSize, options: [.new]) { it, _ in
            let s = it.presentationSize
            guard s.width > 0, s.height > 0 else { return }
            DispatchQueue.main.async {
                resolution = "\(Int(s.width))×\(Int(s.height))"
                if s.height >= 2000 { hdr = "4K" }
                else if s.height >= 1000 { hdr = "FHD" }
                else { hdr = "" }
            }
        }

        // 码率 + 色彩信息：access log
        logObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry, object: item, queue: .main
        ) { _ in
            guard let e = item.accessLog()?.events.last else { return }
            let mbps = e.observedBitrate / 1_000_000
            if mbps > 0 { bitrate = String(format: "%.1f", mbps) }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { note in
            let e = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            error = e?.localizedDescription ?? "播放失败"
        }
    }

    /// 设定定时关闭
    private func applySleepTimer(_ minutes: Int?) {
        sleepMinutes = minutes
        if let m = minutes {
            sleepDeadline = Date().addingTimeInterval(Double(m) * 60)
            sleepRemaining = m * 60
            startSleepTicker()
        } else {
            sleepDeadline = nil
            sleepRemaining = 0
        }
    }

    private func startSleepTicker() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            guard let deadline = sleepDeadline else { t.invalidate(); return }
            let left = Int(deadline.timeIntervalSinceNow)
            if left <= 0 {
                t.invalidate()
                player?.pause()
                sleepMinutes = nil
                sleepDeadline = nil
                sleepRemaining = 0
            } else {
                sleepRemaining = left
            }
        }
    }

    private func stop() {
        sizeObserver?.invalidate()
        if let logObserver { NotificationCenter.default.removeObserver(logObserver) }
        player?.pause()
    }
}
