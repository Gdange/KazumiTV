import SwiftUI
import AVKit

/// 播放页：AVPlayer + 倍速 / 清晰度 / 弹幕开关
struct PlayScreen: View {
    let target: PlaybackTarget
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var rate: Float = 1.0
    @State private var danmakuOn = true
    @State private var danmaku: [DanmakuEntry] = []
    @State private var danmakuStatus = ""
    @State private var showControls = true
    @State private var playing = false
    @State private var duration: Double = 0
    @State private var position: Double = 0
    @State private var timeObserver: Any?

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 54)).foregroundStyle(.orange)
                    Text(error)
                        .font(.system(size: 19)).multilineTextAlignment(.center)
                        .padding(.horizontal, 80)
                    Button("返回") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 10)
                }
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()

                // 顶部标题 + 返回
                VStack {
                    HStack(spacing: 14) {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)

                        Text(title)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(.black.opacity(0.55)))
                        Spacer()
                    }
                    .padding(.horizontal, 44).padding(.top, 36)
                    Spacer()
                }

                // 底部控制条
                VStack {
                    Spacer()
                    controlBar
                }

                if danmakuOn && !danmaku.isEmpty {
                    DanmakuLayer(entries: danmaku, time: position)
                        .allowsHitTesting(false)
                }
            } else {
                ProgressView("正在加载…")
                    .font(.system(size: 18))
            }
        }
        .onAppear(perform: start)
        .onDisappear { cleanup() }
    }

    // MARK: 控制条
    private var controlBar: some View {
        HStack(spacing: 18) {
            // 倍速
            Menu {
                ForEach(rates, id: \.self) { r in
                    Button(rateLabel(r)) { setRate(r) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer").font(.system(size: 14))
                    Text(rateLabel(rate)).font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.6)))
            }

            // 清晰度（m3u8 多码率时由系统自动选择，这里只作提示）
            Menu {
                Button("自动") { }
                Text("当前源为单码率")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 14))
                    Text("自动").font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.6)))
            }

            // 弹幕开关
            Button {
                danmakuOn.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: danmakuOn ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 14))
                    Text("弹幕").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(danmakuOn ? .black : .white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(danmakuOn ? KZ.accent : .black.opacity(0.6)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(timeText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(.black.opacity(0.6)))
        }
        .padding(.horizontal, 44).padding(.bottom, 44)
    }

    private var timeText: String {
        let p = Int(position), d = Int(duration)
        return String(format: "%02d:%02d / %02d:%02d", p / 60, p % 60, d / 60, d % 60)
    }

    private func rateLabel(_ r: Float) -> String {
        r == 1.0 ? "正常" : String(format: "%gx", r)
    }

    private func setRate(_ r: Float) {
        rate = r
        player?.rate = r
    }

    // MARK: 播放
    private func start() {
        switch target.drm {
        case .unsupported(let reason):
            error = reason
            return
        case .fairPlay:
            error = "FairPlay 流暂不支持"
            return
        case .none:
            break
        }

        let asset = AVURLAsset(url: target.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": target.headers
        ])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        player = p

        // 进度 + 时长
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { t in
            position = t.seconds
        }

        Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if item.status == .readyToPlay {
                    duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    p.rate = rate
                    playing = true
                    Task { await loadDanmaku() }
                    return
                }
                if item.status == .failed {
                    error = "播放失败：\(item.error?.localizedDescription ?? "未知")"
                    return
                }
            }
            if item.status != .readyToPlay {
                error = "加载超时（20 秒）"
            }
        }
    }

    /// 按番名 + 集数拉弹幕
    private func loadDanmaku() async {
        guard danmaku.isEmpty else { return }
        // 从标题里猜集数（"第01集" / "01" / "1"）
        let ep = extractEpisodeNumber(title)
        danmakuStatus = "正在找弹幕…"
        do {
            let list = try await DanmakuAPI.searchEpisodes(anime: cleanTitle(title))
            guard let match = list.first(where: { $0.ep == ep }) ?? list.first else {
                danmakuStatus = "没有匹配的弹幕库"
                return
            }
            danmaku = try await DanmakuAPI.comments(episodeId: match.id)
            danmakuStatus = danmaku.isEmpty ? "这集没有弹幕" : "弹幕 \(danmaku.count) 条"
        } catch {
            danmakuStatus = error.localizedDescription
        }
    }

    private func cleanTitle(_ s: String) -> String {
        s.replacingOccurrences(of: #"第\s*\d+\s*[集话]"#, with: "", options: .regularExpression)
         .trimmingCharacters(in: .whitespaces)
    }

    private func extractEpisodeNumber(_ s: String) -> Int {
        if let m = s.range(of: #"\d+"#, options: .regularExpression) {
            return Int(s[m]) ?? 1
        }
        return 1
    }

    private func cleanup() {
        if let t = timeObserver { player?.removeTimeObserver(t) }
        player?.pause()
        player = nil
    }
}
