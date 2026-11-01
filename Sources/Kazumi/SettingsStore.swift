import Foundation
import SwiftUI

/// 设置项（对齐官方 SettingsKeys 中 tvOS 适用的部分）
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // 播放
    @AppStorage("kz.autoPlay")            var autoPlay = true
    @AppStorage("kz.autoPlayNext")        var autoPlayNext = true
    @AppStorage("kz.rememberProgress")    var rememberProgress = true
    @AppStorage("kz.skipIntroSeconds")    var skipIntroSeconds = 0

    // 资源
    @AppStorage("kz.checkPluginUpdate")   var checkPluginUpdate = true
    @AppStorage("kz.bangumiAcceleration") var bangumiAcceleration = false

    // 界面
    @AppStorage("kz.appearance")          var appearance = "dark"   // dark / light / system
    @AppStorage("kz.lowMemoryMode")       var lowMemoryMode = false

    // 弹幕
    @AppStorage("kz.danmakuEnabled")      var danmakuEnabled = true
    @AppStorage("kz.danmakuFontSize")     var danmakuFontSize = 24
    @AppStorage("kz.danmakuOpacity")      var danmakuOpacity = 80
    @AppStorage("kz.danmakuSpeed")        var danmakuSpeed = 100
    @AppStorage("kz.danmakuArea")         var danmakuArea = 50

    private init() {}
}
