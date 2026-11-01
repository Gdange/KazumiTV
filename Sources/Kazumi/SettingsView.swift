import SwiftUI

/// 设置：照官方四分组（播放 / 资源 / 应用 / 其他）
struct SettingsView: View {
    @StateObject private var s = SettingsStore.shared
    @State private var section: Section = .player
    @State private var showRules = false
    @State private var installedCount = RuleCatalog.installed().count

    enum Section: String, CaseIterable, Identifiable {
        case account = "账号"
        case player = "播放"
        case resource = "资源"
        case rules = "规则"
        case app = "应用"
        case other = "其他"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .account: return "person.crop.circle"
            case .player: return "play.rectangle"
            case .resource: return "square.stack.3d.up"
            case .rules: return "list.bullet.rectangle"
            case .app: return "gearshape"
            case .other: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            menu
            Divider().overlay(KZ.line)
            detail
        }
        .background(KZ.bg.ignoresSafeArea())
    }

    private var menu: some View {
        HStack(spacing: 10) {
            ForEach(Section.allCases) { sec in
                MenuRow(section: sec, selected: section == sec) { section = sec }
            }
            Spacer()
        }
    }

    // MARK: 账号

    @State private var tokenInput = ""
    @State private var loggingIn = false
    @State private var loginMessage: String?

    private var accountPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bangumi 账号")
                .font(.system(size: 17, weight: .semibold))

            Text("登录后可同步追番、发布评分与短评。Token 在 bangumi.tv → 个人设置 → 开放接口 里创建。")
                .font(.system(size: 13))
                .foregroundStyle(KZ.dim)
                .fixedSize(horizontal: false, vertical: true)

            if let name = BangumiAccount.username, BangumiAccount.isLoggedIn {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(KZ.accent)
                    Text("已登录：\(name)").font(.system(size: 15))
                    Spacer()
                    Button {
                        BangumiAccount.logout()
                        loginMessage = "已退出"
                    } label: {
                        Text("退出")
                            .font(.system(size: 14))
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Capsule().fill(KZ.card))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card.opacity(0.6)))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("粘贴 Access Token", text: $tokenInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card))

                    HStack(spacing: 12) {
                        Button { Task { await doLogin() } } label: {
                            HStack(spacing: 8) {
                                if loggingIn { ProgressView().scaleEffect(0.7) }
                                Text(loggingIn ? "验证中…" : "登录")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KZ.onAccent)
                            .padding(.horizontal, 26).padding(.vertical, 10)
                            .background(Capsule().fill(KZ.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(loggingIn || tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)

                        if let m = loginMessage {
                            Text(m).font(.system(size: 13))
                                .foregroundStyle(m.contains("失败") ? .orange : KZ.dim)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 12).fill(KZ.card.opacity(0.35)))
    }

    private func doLogin() async {
        let t = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        loggingIn = true
        loginMessage = nil
        defer { loggingIn = false }

        if let name = await BangumiAPI.me(token: t) {
            BangumiAccount.token = t
            BangumiAccount.username = name
            loginMessage = "登录成功"
            tokenInput = ""
        } else {
            loginMessage = "验证失败，Token 无效或网络不通"
        }
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch section {
                case .account:  accountPanel
                case .player:   playerPanel
                case .resource: resourcePanel
                case .rules:    RuleStoreView()
                case .app:      appPanel
                case .other:    otherPanel
                }
            }
            .padding(.bottom, 50)
        }
    }

    // MARK: 播放
    private var playerPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("播放", "播放器行为")
            toggleRow("自动播放", "进入详情页后自动开始", $s.autoPlay)
            toggleRow("自动下一集", "播完自动跳转", $s.autoPlayNext)
            toggleRow("记住播放进度", "下次从上次位置继续", $s.rememberProgress)
            stepperRow("跳过片头", "\(s.skipIntroSeconds) 秒", 0...120, 5, $s.skipIntroSeconds)
        }
    }

    // MARK: 资源
    private var resourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("资源", "规则与数据源")
            toggleRow("启动时检查规则更新", "对齐官方行为", $s.checkPluginUpdate)
            toggleRow("Bangumi 加速", "使用镜像站点", $s.bangumiAcceleration)
            rowShell {
                HStack {
                    Text("规则管理").font(.system(size: 16))
                    Spacer()
                    Text("见上方「规则」标签").font(.system(size: 13)).foregroundStyle(KZ.dim)
                }
            }
        }
    }

    // MARK: 应用
    private var appPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("应用", "外观与性能")
            pickerRow("外观", ["深色", "浅色", "跟随系统"], current: appearanceIndex) { idx in
                s.appearance = ["dark", "light", "system"][idx]
            }
            toggleRow("低内存模式", "减少图片与缓冲", $s.lowMemoryMode)
            toggleRow("弹幕", "默认开启弹幕", $s.danmakuEnabled)
            stepperRow("弹幕字号", "\(s.danmakuFontSize)", 12...48, 2, $s.danmakuFontSize)
            stepperRow("弹幕不透明度", "\(s.danmakuOpacity)%", 20...100, 10, $s.danmakuOpacity)
            credentialRow("弹弹play AppId", "kz.danmakuAppId")
            credentialRow("弹弹play AppSecret", "kz.danmakuSecret")
        }
    }

    // MARK: 其他
    private var otherPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("其他", "关于本应用")
            rowShell {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kazumi TV").font(.system(size: 16, weight: .medium))
                    Text("Apple TV 上的番剧采集客户端，规则与数据来自开源项目 Kazumi")
                        .font(.system(size: 13)).foregroundStyle(KZ.dim)
                }
            }
            kvRow("版本", "0.1.0")
            kvRow("规则来源", "KazumiRules（官方仓库）")
            kvRow("追番", "\(CollectionStore.shared.items.count) 部")
        }
    }

    private var appearanceIndex: Int {
        ["dark", "light", "system"].firstIndex(of: s.appearance) ?? 0
    }

    // MARK: 组件
    private func header(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(.system(size: 28, weight: .bold))
            Text(sub).font(.system(size: 14)).foregroundStyle(KZ.dim)
        }.padding(.bottom, 10)
    }

    private func rowShell<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card))
    }

    private func toggleRow(_ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        rowShell {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16))
                    Text(sub).font(.system(size: 12)).foregroundStyle(KZ.dim)
                }
                Spacer()
                Toggle("", isOn: binding).labelsHidden()
            }
        }
    }

    private func stepperRow(_ title: String, _ value: String, _ range: ClosedRange<Int>,
                            _ step: Int, _ binding: Binding<Int>) -> some View {
        rowShell {
            HStack {
                Text(title).font(.system(size: 16))
                Spacer()
                Text(value).foregroundStyle(KZ.dim).frame(width: 90, alignment: .trailing)
                // tvOS 没有 Stepper，用两个圆角按钮代替
                Button { binding.wrappedValue = max(range.lowerBound, binding.wrappedValue - step) } label: {
                    Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(KZ.card))
                }.buttonStyle(.plain)
                Button { binding.wrappedValue = min(range.upperBound, binding.wrappedValue + step) } label: {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(KZ.card))
                }.buttonStyle(.plain)
            }
        }
    }

    private func pickerRow(_ title: String, _ options: [String], current: Int,
                           _ onPick: @escaping (Int) -> Void) -> some View {
        rowShell {
            HStack {
                Text(title).font(.system(size: 16))
                Spacer()
                ForEach(Array(options.enumerated()), id: \.offset) { idx, name in
                    Button { onPick(idx) } label: {
                        Text(name)
                            .font(.system(size: 14, weight: current == idx ? .semibold : .regular))
                            .foregroundStyle(current == idx ? KZ.onAccent : KZ.label)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(current == idx ? KZ.accent : KZ.line))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 凭据输入行（tvOS 上弹出系统键盘）
    private func credentialRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title).font(.system(size: 16))
            Spacer()
            TextField("未填写", text: Binding(
                get: { UserDefaults.standard.string(forKey: key) ?? "" },
                set: { UserDefaults.standard.set($0, forKey: key) }
            ))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 14, design: .monospaced))
            .frame(width: 420)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(KZ.card))
    }

    private func kvRow(_ k: String, _ v: String) -> some View {
        rowShell {
            HStack {
                Text(k).font(.system(size: 16))
                Spacer()
                Text(v).foregroundStyle(KZ.dim)
            }
        }
    }
}

struct MenuRow: View {
    let section: SettingsView.Section
    let selected: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.icon).font(.system(size: 15))
                Text(section.rawValue).font(.system(size: 16, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? KZ.onAccent : KZ.label)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Capsule().fill(selected ? KZ.accent : (focused ? KZ.card : KZ.card.opacity(0.5))))
            .scaleEffect(focused ? 1.04 : 1.0)
            .animation(.easeOut(duration: 0.14), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
    }
}
