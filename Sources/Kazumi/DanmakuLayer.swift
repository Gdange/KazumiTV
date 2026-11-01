import SwiftUI

/// 弹幕渲染层：按时间轴滚动，8 条轨道避让
struct DanmakuLayer: View {
    let entries: [DanmakuEntry]
    let time: Double

    private let laneCount = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let laneH = (geo.size.height * 0.5) / CGFloat(laneCount)

            ZStack(alignment: .topLeading) {
                ForEach(visible) { e in
                    let lane = abs(e.text.hashValue) % laneCount
                    let elapsed = time - e.time
                    // 8 秒从右划到左
                    let progress = min(1.0, elapsed / 8.0)
                    let x = w - CGFloat(progress) * (w + 420)

                    Text(e.text)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.85), radius: 2, x: 1, y: 1)
                        .fixedSize()
                        .offset(x: x, y: 60 + CGFloat(lane) * laneH)
                        .opacity(elapsed > 7.6 ? (8.0 - elapsed) / 0.4 : 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// 只渲染时间窗内的弹幕，避免长时间播放堆积
    private var visible: [DanmakuEntry] {
        entries.filter { time >= $0.time && time - $0.time < 8.0 }
    }
}
