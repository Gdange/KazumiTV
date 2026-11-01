import SwiftUI

/// 顶层导航：推荐 / 时间表 / 追番 / 我的（对齐官方四个 tab）
struct RootView: View {
    let rules: [KazumiRule]

    var body: some View {
        TabView {
            PopularView()
                .tabItem { Label("推荐", systemImage: "house.fill") }
            ScheduleView()
                .tabItem { Label("时间表", systemImage: "calendar") }
            CollectionView()
                .tabItem { Label("追番", systemImage: "heart.fill") }
            SettingsView()
                .tabItem { Label("我的", systemImage: "gearshape.fill") }
        }
        .background(KZ.bg)
        .overlay(AutoPlayRunner().allowsHitTesting(false))
    }
}
