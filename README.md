<div align="center">

# KazumiTV

**Apple TV 上的番剧采集客户端**

基于 [Kazumi](https://github.com/Predidit/Kazumi) 的规则体系，用 SwiftUI 原生重写

[![Platform](https://img.shields.io/badge/platform-tvOS%2017%2B-black)](https://developer.apple.com/tvos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

</div>

---

## 这是什么

Kazumi 是一个用 Flutter 写的跨平台番剧客户端，支持 Windows / macOS / Linux / Android / iOS。

**KazumiTV 是它的 tvOS 原生实现**——因为 Flutter 不支持 tvOS（Apple TV），无法直接移植，只能用 SwiftUI 重写整个界面层。

规则格式、数据接口、播放解析语义完全兼容 KazumiRules。

## 功能

| 已完成 | 说明 |
|---|---|
| 🔍 搜索 | 番剧搜索（Bangumi 数据） + 片源搜索，支持 `tag:` / `sort:` / `score:` 语法 |
| 🏠 推荐 | 热门番组 + 15 个官方分类标签 |
| 📅 时间表 | 一周放送表，显示每日番组数量与评分 |
| ❤️ 追番 | 5 种状态（在看/想看/看过/搁置/抛弃）+ 网格/列表双视图 |
| 📺 播放 | AVPlayer，支持倍速（0.5x–2x）、进度显示 |
| 🎬 解析 | MacCMS 播放页解析，纯 HTTP 无 WebView |
| 📋 规则 | 官方规则仓库在线安装 / 删除，8 源自动匹配 |
| 🎨 主题 | 深色 / 浅色 / 跟随系统 |

| 待完成 | 说明 |
|---|---|
| 💬 弹幕 | 渲染层已就绪，需弹弹play AppId（[申请](https://dev.dandanplay.com/)） |
| 🖼️ 超分辨率 | Anime4K 需移植 Metal shader |
| 🔄 Bangumi 同步 | tvOS 无浏览器，OAuth 回调走不通 |

## 技术要点

### MacCMS 播放解析（纯 Swift，无 WebView）

tvOS **没有 WebKit**，无法用 Kazumi 那套隐藏 WebView 截获 m3u8 的方式。

但这不代表做不了——拆开看，MacCMS 的"JS 动态解析"其实只是几步 HTTP：

```
① 播放页 HTML    var player_aaaa = {"url": "...", "from": "YDY", "encrypt": 0}
② 静态配置       playerconfig.js → player_list["YDY"].parse
③ 解析器页面     GET {parse}?url={encrypted}
④ 服务端解密     POST api_config.php {url, key, time} → 明文 m3u8/mp4
```

加密全在服务端，客户端只需发 POST。全程 `URLSession`，零外部依赖。

`encrypt` 字段的三种取值：

| 值 | 处理方式 |
|---|---|
| 0 | 直接是地址，或走解析器 |
| 1 | `URLDecode(raw)` |
| 2 | `base64 → URLDecode`（7sefun 等站） |

### tvOS 焦点引擎

每个可聚焦区域用 `.focusSection()` 划区，否则方向键行为不可预测。

页面跳转用 `fullScreenCover` 而非 `navigationDestination`——同一个 `NavigationStack` 里只能有一个 destination，多个会静默失效。

## 构建

需要 Xcode 15+ 和 tvOS 17+ SDK。

```bash
# 安装 xcodegen
brew install xcodegen

# 生成工程
cd src/tvOSClient && xcodegen generate

# 模拟器运行
xcodebuild -scheme QYTV -destination 'platform=tvOS Simulator,name=Apple TV' build

# 真机自签（需先配对 Apple TV）
./build-tvos.sh
```

## 目录结构

```
Sources/
├── App.swift                    入口
├── Source.swift                 通用 Source 协议（可插拔数据源）
└── Kazumi/
    ├── RuleCatalog.swift        官方规则仓库（index.json + 镜像回退）
    ├── RuleEngine.swift         XPath 规则解析（行内查询语义）
    ├── XPathDoc.swift           libxml2 封装
    ├── MacCMSResolver.swift     播放地址解析（核心）
    ├── BangumiAPI.swift         Bangumi 数据
    ├── BangumiExtras.swift      角色/制作/关联/吐槽
    ├── SearchParser.swift       官方搜索语法
    ├── PopularView.swift        推荐页
    ├── ScheduleView.swift       时间表
    ├── CollectionView.swift     追番
    ├── DetailView.swift         详情页（五 Tab）
    ├── PlayerScreen.swift       播放器
    ├── DanmakuLayer.swift       弹幕渲染
    └── rules/                   内置规则（KazumiRules）
```

## 关于规则

规则来自 [KazumiRules](https://github.com/Predidit/KazumiRules)，格式是 6 个 XPath 字段：

```json
{
  "name": "站点名",
  "baseURL": "https://...",
  "searchURL": "/search?wd=@keyword",
  "searchList": "//div[...]",
  "searchName": "//a",
  "searchResult": "//a",
  "chapterRoads": "//div[...]",
  "chapterResult": "//ul/li/a"
}
```

**关键语义**：规则里的 `//a` 指的是「当前行内的 a」，实现时必须当成 `.//a` 在行节点下查询，否则会把页面所有链接都匹配进来。

## 致谢

- [Kazumi](https://github.com/Predidit/Kazumi) — 规则体系、UI 设计、数据接口
- [KazumiRules](https://github.com/Predidit/KazumiRules) — 规则仓库
- [Bangumi](https://bgm.tv/) — 番剧数据

## 许可

GPL-3.0，与 Kazumi 主项目一致。
