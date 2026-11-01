import SwiftUI
import UIKit

/// 配色取自 Kazumi 官方 App（Material 3 / seed 绿），深色 + 浅色两套自动切换
enum KZ {

    /// 动态颜色：跟随系统 colorScheme（由 preferredColorScheme 控制）
    private static func dyn(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    /// 强调色：Kazumi 的淡黄绿（截图取色 #C1E699，浅色模式用深一点的 #7A9B4E）
    static let accent = dyn(
        dark: UIColor(red: 0xC1/255, green: 0xE6/255, blue: 0x99/255, alpha: 1),
        light: UIColor(red: 0x6B/255, green: 0x8C/255, blue: 0x3D/255, alpha: 1)
    )

    /// 强调色上的文字（深色模式下用深字，浅色模式下用白字）
    static let onAccent = dyn(
        dark: UIColor(red: 0x10/255, green: 0x12/255, blue: 0x0C/255, alpha: 1),
        light: UIColor.white
    )

    /// 页面背景
    static let bg = dyn(
        dark: UIColor(red: 0x10/255, green: 0x12/255, blue: 0x0C/255, alpha: 1),
        light: UIColor(red: 0xF8/255, green: 0xFB/255, blue: 0xF2/255, alpha: 1)
    )

    /// 卡片底
    static let card = dyn(
        dark: UIColor(red: 0x1B/255, green: 0x1E/255, blue: 0x17/255, alpha: 1),
        light: UIColor(red: 0xEC/255, green: 0xF0/255, blue: 0xE4/255, alpha: 1)
    )

    /// 主文字
    static let label = dyn(
        dark: UIColor.white,
        light: UIColor(red: 0x1A/255, green: 0x1E/255, blue: 0x14/255, alpha: 1)
    )

    /// 次级文字
    static let dim = dyn(
        dark: UIColor(red: 0x9A/255, green: 0xA0/255, blue: 0x8C/255, alpha: 1),
        light: UIColor(red: 0x6E/255, green: 0x75/255, blue: 0x62/255, alpha: 1)
    )

    /// 分隔线
    static let line = dyn(
        dark: UIColor.white.withAlphaComponent(0.08),
        light: UIColor.black.withAlphaComponent(0.08)
    )

    // 官方常量（lib/utils/constants.dart）
    static let cardSpace: CGFloat = 8
    static let safeSpace: CGFloat = 12
    static let imgRadius: CGFloat = 12
    static let posterRatio: CGFloat = 0.65   // 官方 mainAxisExtent 反推
    static let columns = 6                   // 官方宽屏列数
}

/// 焦点时的卡片样式
struct FocusCard: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(focused ? 1.08 : 1.0)
            .shadow(color: focused ? KZ.accent.opacity(0.45) : .clear, radius: 18, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: KZ.imgRadius)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 3)
            )
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

extension View {
    func focusCard(_ focused: Bool) -> some View { modifier(FocusCard(focused: focused)) }
}


/// 小元素（标签、切换按钮）的焦点样式：描边 + 提亮，不放大
struct FocusChip: ViewModifier {
    var focused: Bool
    var corner: CGFloat = 999
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .strokeBorder(focused ? KZ.accent : .clear, lineWidth: 2.5)
            )
            .shadow(color: focused ? KZ.accent.opacity(0.5) : .clear, radius: 10)
            .scaleEffect(focused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// 列表行的焦点样式：左侧高亮条 + 淡色背景
struct FocusRow: ViewModifier {
    var focused: Bool
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(focused ? KZ.accent.opacity(0.16) : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(focused ? KZ.accent : .clear)
                    .frame(width: 4)
                    .padding(.vertical, 10)
            }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

extension View {
    func focusChip(_ focused: Bool, corner: CGFloat = 999) -> some View {
        modifier(FocusChip(focused: focused, corner: corner))
    }
    func focusRow(_ focused: Bool) -> some View { modifier(FocusRow(focused: focused)) }
}
