import SwiftUI

@main
struct QYTVApp: App {
    @State private var rules: [KazumiRule] = RulesStore.loadBundled()

    init() {
        // 全局 URL 缓存：图片/接口响应落到磁盘，二次访问不再走网络
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "kz_http_cache"
        )
    }
    @AppStorage("kz.appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            if rules.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "tray").font(.system(size: 56)).foregroundStyle(.tertiary)
                    Text("没有加载到规则").font(.system(size: 22))
                }
            } else {
                RootView(rules: rules)
                    .preferredColorScheme(colorScheme)
            }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil      // 跟随系统
        }
    }
}
