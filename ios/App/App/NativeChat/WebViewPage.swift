import SwiftUI
import WebKit

extension Notification.Name {
    static let alcoveShowPermissions = Notification.Name("alcoveShowPermissions")
    static let alcoveJumpToMessage = Notification.Name("alcoveJumpToMessage")
    static let alcoveRequestJumpToMessage = Notification.Name("alcoveRequestJumpToMessage")
    // 0904 长卡片（晨报 / Inside）收起后把那条消息滚回屏幕中间，object 是 ChatMessage.id（0922 起是 ts|role 字符串）
    static let alcoveRecenterMessage = Notification.Name("alcoveRecenterMessage")
    // 0904 整页（工作室 / 共读室…）关掉回到主聊天：主聊天在被盖住时收不到键盘收起，列表停在被键盘撑高的位置
    static let alcoveHouseClosed = Notification.Name("alcoveHouseClosed")
}

// 常驻共享 WebView：app 启动就后台加载 PWA，按钮点开秒进对应页面，
// 大厅/清单/音乐/终端这些功能全部走原页面本体，一个不少
final class WebHouse: NSObject, WKNavigationDelegate {
    static let shared = WebHouse()

    let webView: WKWebView
    private var loaded = false
    private var pendingJS: [String] = []

    override private init() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        super.init()
        webView.navigationDelegate = self
        // UA 标记：PWA 借此识别自己跑在 app 里（设置页显示"系统权限"板块）
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] ua, _ in
            if let ua = ua as? String {
                self?.webView.customUserAgent = ua + " AlcoveApp"
            }
            self?.webView.load(URLRequest(url: AlcoveAPI.base))
        }
    }

    func warmUp() { _ = webView } // 触发懒加载

    func run(_ js: String) {
        if loaded {
            webView.evaluateJavaScript(js, completionHandler: nil)
        } else {
            pendingJS.append(js)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        // 原生聊天页已经接管聊天，把 WebView 里的 PWA 聊天层永久藏掉：
        // 面板/抽屉打开时浮在干净壁纸上，看起来就是纯功能页
        let hideChat = """
        (function(){var st=document.createElement('style');st.id='alcove-app-hide';
        st.textContent='#page-chat .chat-messages,#page-chat .chat-input-bar,#page-chat .chat-topbar,#page-chat .chat-fade-top,.clawd-pet,.scroll-bottom-btn{display:none!important}';
        if(!document.getElementById('alcove-app-hide'))document.head.appendChild(st);})();
        """
        webView.evaluateJavaScript(hideChat, completionHandler: nil)
        for js in pendingJS { webView.evaluateJavaScript(js, completionHandler: nil) }
        pendingJS.removeAll()
        syncProfile()
    }

    // 从 PWA 的 localStorage 同步名字和头像给原生顶栏
    // （她在 app 的 Settings 里改完，回聊天页就生效）
    func syncProfile() {
        webView.evaluateJavaScript("localStorage.getItem('alcove-ai-name') || ''") { v, _ in
            if let name = v as? String, !name.isEmpty {
                UserDefaults.standard.set(name, forKey: "assistantName")
            }
        }
        webView.evaluateJavaScript("localStorage.getItem('haven-ai-avatar') || ''") { v, _ in
            if let avatar = v as? String, !avatar.isEmpty {
                UserDefaults.standard.set(avatar, forKey: "assistantAvatarDataURL")
            }
        }
        // 0827 拆掉：这里原来把网页 localStorage 里的 alcove-theme 抄回 alcoveTheme，
        // 网页那份是死的旧值，每次 WebView 出现就把她刚按下的白天冲回黑夜。
        // 主题现在只由原生设置页那一个开关写。
        webView.evaluateJavaScript("localStorage.getItem('haven-font-size') || '15'") { v, _ in
            if let s = v as? String, let n = Int(s), (10...24).contains(n) {
                UserDefaults.standard.set(n, forKey: "chatFontSize")
            }
        }
        // 她换的自定义聊天壁纸（per-theme），落成文件给原生页用
        syncWallpaper(storageKey: "alcove-chat-wallpaper", file: "chatwall_haven.jpg")
        syncWallpaper(storageKey: "alcove-chat-wallpaper--midnight", file: "chatwall_midnight.jpg")
    }

    private func syncWallpaper(storageKey: String, file: String) {
        webView.evaluateJavaScript("localStorage.getItem('\(storageKey)') || ''") { v, _ in
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dst = dir.appendingPathComponent(file)
            guard let dataURL = v as? String, !dataURL.isEmpty else {
                // 她清掉了自定义壁纸，本地文件跟着删
                if FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.removeItem(at: dst)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "wallStamp")
                }
                return
            }
            let b64 = dataURL.contains(",")
                ? String(dataURL.split(separator: ",", maxSplits: 1)[1]) : dataURL
            if let data = Data(base64Encoded: b64) {
                try? data.write(to: dst)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "wallStamp")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded = false
    }

    // 拦 alcove:// 内部跳转：设置页"系统权限"入口走这里弹原生页
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme == "alcove" {
            decisionHandler(.cancel)
            if url.host == "permissions" {
                NotificationCenter.default.post(name: .alcoveShowPermissions, object: nil)
            }
            return
        }
        decisionHandler(.allow)
    }

    func reloadIfNeeded() {
        if webView.url == nil || !loaded {
            loaded = false
            webView.load(URLRequest(url: AlcoveAPI.base))
        }
    }
}

// 把共享 WebView 挂进 SwiftUI 视图树
struct HouseWebView: UIViewRepresentable {
    let onPresentJS: String?

    func makeUIView(context: Context) -> WKWebView {
        let house = WebHouse.shared
        house.reloadIfNeeded()
        if let js = onPresentJS { house.run(js) }
        return house.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// 全屏打开某个 PWA 页面（present 时执行跳转 JS）
struct HousePage: View {
    let js: String?
    var dismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            HouseWebView(onPresentJS: js)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.42, green: 0.40, blue: 0.41))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(Color(red: 210/255, green: 210/255, blue: 218/255).opacity(0.3), lineWidth: 1))
            }
            .padding(.leading, 14)
            .padding(.top, 6)
        }
    }
}
