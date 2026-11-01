import SwiftUI
import AVFoundation

/// 视频详情（对齐官方「视频详情」）
/// 读 AVPlayerItem 的轨道信息：编码、分辨率、帧率、码率、音轨
struct VideoInfoSheet: View {
    let item: AVPlayerItem?
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("视频详情").font(.system(size: 24, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).padding(8)
                }.buttonStyle(.plain)
            }

            if rows.isEmpty {
                ProgressView("读取中…").padding(.top, 30)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            HStack {
                                Text(row.0).font(.system(size: 14)).foregroundStyle(KZ.dim)
                                Spacer()
                                Text(row.1)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundStyle(KZ.label)
                            }
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            if i < rows.count - 1 { Divider().opacity(0.2) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card.opacity(0.5)))
                }
            }
        }
        .padding(36)
        .frame(width: 720, height: 620)
        .background(KZ.bg)
        .task { await load() }
    }

    private func load() async {
        guard let item else { return }
        var out: [(String, String)] = []

        // 分辨率
        let size = item.presentationSize
        if size.width > 0 {
            out.append(("分辨率", "\(Int(size.width))×\(Int(size.height))"))
        }

        // 视频轨
        if let v = item.tracks.first(where: { $0.assetTrack?.mediaType == .video })?.assetTrack {
            let fps = v.nominalFrameRate
            if fps > 0 { out.append(("帧率", String(format: "%.2f fps", fps))) }

            if let fd = v.formatDescriptions.first {
                let desc = fd as! CMFormatDescription
                let codec = fourCC(CMFormatDescriptionGetMediaSubType(desc))
                out.append(("视频编码", codec))

                if let dims = CMVideoFormatDescriptionGetDimensions(desc) as CMVideoDimensions? {
                    out.append(("编码分辨率", "\(dims.width)×\(dims.height)"))
                }
            }

            // 码率
            if let rate = try? await v.load(.estimatedDataRate), rate > 0 {
                out.append(("视频码率", String(format: "%.2f Mbps", rate / 1_000_000)))
            }
            // 色彩特性（同步属性）
            if v.hasMediaCharacteristic(.containsHDRVideo) {
                out.append(("HDR", "支持"))
            }
        }

        // 音轨
        if let a = item.tracks.first(where: { $0.assetTrack?.mediaType == .audio })?.assetTrack {
            if let fd = a.formatDescriptions.first {
                let desc = fd as! CMFormatDescription
                out.append(("音频编码", fourCC(CMFormatDescriptionGetMediaSubType(desc))))
            }
            if let ch = try? await a.load(.estimatedDataRate), ch > 0 {
                out.append(("音频码率", String(format: "%.0f kbps", ch / 1000)))
            }
        }

        // 时长与缓冲
        if let d = try? await item.asset.load(.duration), d.seconds.isFinite {
            out.append(("时长", formatTime(d.seconds)))
        }
        if let log = item.accessLog()?.events.last {
            if log.observedBitrate > 0 {
                out.append(("实时码率", String(format: "%.2f Mbps", log.observedBitrate / 1_000_000)))
            }
            if log.numberOfDroppedVideoFrames > 0 {
                out.append(("丢帧", "\(log.numberOfDroppedVideoFrames)"))
            }
        }

        rows = out
    }

    private func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let s = String(bytes: bytes, encoding: .ascii) ?? "?"
        switch s {
        case "avc1": return "H.264 (avc1)"
        case "hvc1", "hev1": return "HEVC (hvc1)"
        case "vp09": return "VP9"
        case "av01": return "AV1"
        case "mp4a": return "AAC (mp4a)"
        case "ec-3": return "E-AC-3"
        case "ac-3": return "AC-3"
        case "alac": return "ALAC"
        default: return s
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}
