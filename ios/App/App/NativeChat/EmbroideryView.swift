import SwiftUI
import WebKit
import PhotosUI
import Photos

// The same WKWebView stays mounted when expanding; its document, selection and undo stack survive.
struct EmbroideryView: View {
    @Binding var isPresented: Bool
    @AppStorage(AlcoveAppearance.key) private var appearance = "light"
    @State private var full = false
    @State private var photo: PhotosPickerItem?
    @State private var pickingPhoto = false
    @StateObject private var session: EmbroiderySession

    init(isPresented: Binding<Bool>, startFull: Bool = false, workID: String? = nil, replay: Bool = false) {
        _isPresented = isPresented
        _full = State(initialValue: startFull)
        _session = StateObject(wrappedValue: EmbroiderySession(workID: workID, replay: replay))
    }

    private var insets: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.safeAreaInsets ?? .zero
    }
    var body: some View {
        let _ = appearance
        GeometryReader { root in
            VStack(spacing: 0) {
                if !full { Spacer(minLength: 0) }
                EmbroideryWeb(session: session, night: AlcoveAppearance.isDark,
                              safeTop: full ? insets.top : 0, safeBottom: insets.bottom)
                    .frame(height: full ? root.size.height : root.size.height * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: full ? 0 : 22, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images,
                      preferredItemEncoding: .current)
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let source = UIImage(data: data) else {
                        throw NSError(domain: "Embroidery", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "照片读取失败，请重新选择"])
                    }
                    // Persistent document owns its image bytes, never a temporary Photos URL.
                    let scale = min(1, 1600 / max(source.size.width, source.size.height))
                    let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        source.draw(in: CGRect(origin: .zero, size: size))
                    }
                    guard let bytes = resized.pngData() else { return }
                    await MainActor.run {
                        session.emit("image", ["src": "data:image/png;base64," + bytes.base64EncodedString()])
                        photo = nil
                    }
                } catch {
                    await MainActor.run { session.error(error.localizedDescription); photo = nil }
                }
            }
        }
        .onAppear {
            session.onClose = { isPresented = false }
            session.onToggle = { withAnimation(.easeInOut(duration: 0.22)) { full.toggle() } }
            session.onPick = { pickingPhoto = true }
        }
    }
}

final class EmbroiderySession: NSObject, ObservableObject, WKScriptMessageHandler {
    weak var web: WKWebView?
    var appearancePayload: [String: Any] = [:]
    let initialWorkID: String?
    let initialReplay: Bool
    init(workID: String? = nil, replay: Bool = false) {
        initialWorkID = workID; initialReplay = replay; super.init()
    }
    var onClose: () -> Void = {}
    var onToggle: () -> Void = {}
    var onPick: () -> Void = {}
    private let draft: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("embroidery", isDirectory: true).appendingPathComponent("draft.json")

    func emit(_ kind: String, _ payload: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: [kind, payload]),
              let json = String(data: data, encoding: .utf8) else { return }
        web?.evaluateJavaScript("window.__emb && window.__emb.apply(null, \(json))", completionHandler: nil)
    }
    func error(_ message: String) { emit("error", ["message": message]) }
    private func save(_ document: Any?) -> Bool {
        guard let object = document as? [String: Any] else { error("草稿格式错误"); return false }
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            guard data.count < 32 * 1024 * 1024 else { error("作品图片过多，请先减少图片"); return false }
            try FileManager.default.createDirectory(at: draft.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: draft, options: .atomic)
            emit("saved", [:]); return true
        } catch { self.error("草稿保存失败：\(error.localizedDescription)"); return false }
    }
    private func request(_ action: String, body: [String: Any]?, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let allowed = action.range(of: "^(quilt|works|trash|restore|finish|send|search|doodle|work/emb_[A-Za-z0-9_-]+)$", options: .regularExpression) != nil   // 1012 search：搜素材
        guard allowed else { completion(.failure(URLError(.badURL))); return }
        Task {
            do {
                var request = URLRequest(url: AlcoveAPI.fullURL("/api/pulse-range/embroidery/" + action))
                request.timeoutInterval = 60
                if let body {
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                }
                let (data, response) = try await AlcoveAPI.session.data(for: request)
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), value["ok"] as? Bool == true else {
                    throw NSError(domain: "Embroidery", code: 2, userInfo: [NSLocalizedDescriptionKey: value["error"] as? String ?? "请求失败，作品仍然保留"])
                }
                await MainActor.run { completion(.success(value)) }
            } catch { await MainActor.run { completion(.failure(error)) } }
        }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "ready":
            emit("appearance", appearancePayload)
            if let id = initialWorkID {
                request("work/" + id, body: nil) { result in
                    switch result {
                    case .success(let value):
                        var payload = value
                        payload["replay"] = self.initialReplay
                        self.emit("finished", payload)
                    case .failure(let failure): self.error(failure.localizedDescription)
                    }
                }
            } else if FileManager.default.fileExists(atPath: draft.path) {
                do { let d = try Data(contentsOf: draft); emit("load", try JSONSerialization.jsonObject(with: d)) }
                catch { self.error("原草稿读取失败，未覆盖：\(error.localizedDescription)") }
            }
        case "save": _ = save(body["document"])
        case "close":
            if body["document"] is NSNull || body["document"] == nil { onClose() }
            else if save(body["document"]) { onClose() }
        case "request":
            guard let token = body["token"] as? String, let action = body["action"] as? String else { return }
            request(action, body: body["body"] as? [String: Any]) { result in
                switch result {
                case .success(let value):
                    if action == "finish" {
                        // The server now owns the immutable version. Do not reopen it as an editable draft.
                        try? FileManager.default.removeItem(at: self.draft)
                    }
                    self.emit("response", ["token": token, "result": value])
                case .failure(let failure): self.emit("response", ["token": token, "error": failure.localizedDescription])
                }
            }
        case "toggleFull": onToggle()
        case "pickImage": onPick()
        case "exportPNG":
            guard let encoded = body["png"] as? String, encoded.hasPrefix("data:image/png;base64,"),
                  let data = Data(base64Encoded: String(encoded.dropFirst(22))), UIImage(data: data) != nil else {
                error("图片导出失败"); return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { self.error("没有相册写入权限，请在系统设置中允许保存照片") }; return
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }) { success, failure in
                    DispatchQueue.main.async { self.emit("error", ["message": success ? "已存进相册" : (failure?.localizedDescription ?? "相册保存失败")]) }
                }
            }
        case "exportMedia":
            // 1012 存相册：透明 PNG / 带桌面 JPG / 绣字过程 GIF / 视频
            // 1014 类型放在 media 里：原来叫 kind，跟指令名 kind 撞了，存图从没走到这里
            guard let encoded = body["data"] as? String, let kind = body["media"] as? String,
                  let comma = encoded.firstIndex(of: ","), encoded[..<comma].hasSuffix(";base64"),
                  let data = Data(base64Encoded: String(encoded[encoded.index(after: comma)...])) else {
                error("导出失败"); return
            }
            var videoURL: URL?
            if kind == "video" {
                let ext = encoded.hasPrefix("data:video/mp4") ? "mp4" : "mov"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("embroidery-\(UUID().uuidString).\(ext)")
                do { try data.write(to: url) } catch { self.error("视频写入失败"); return }
                videoURL = url
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { self.error("没有相册写入权限，请在系统设置中允许保存照片") }; return
                }
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    if let videoURL { request.addResource(with: .video, fileURL: videoURL, options: nil) }
                    else { request.addResource(with: .photo, data: data, options: nil) }
                }) { success, failure in
                    if let videoURL { try? FileManager.default.removeItem(at: videoURL) }
                    DispatchQueue.main.async { self.emit("error", ["message": success ? "已存进相册" : (failure?.localizedDescription ?? "相册保存失败")]) }
                }
            }
        case "haptic": UISelectionFeedbackGenerator().selectionChanged()
        default: break
        }
    }
}

private struct EmbroideryWeb: UIViewRepresentable {
    let session: EmbroiderySession
    let night: Bool
    let safeTop: CGFloat
    let safeBottom: CGFloat
    func makeCoordinator() -> EmbroideryAssets { EmbroideryAssets() }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(session, name: "embroidery")
        config.userContentController.addUserScript(WKUserScript(source: "window.NIGHT = \(night);",
                                                               injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.setURLSchemeHandler(context.coordinator, forURLScheme: "emb-asset")
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        session.web = web
        web.load(URLRequest(url: URL(string: "emb-asset://local/embroidery.html")!))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        let paper = night ? UIColor(red: 30/255, green: 31/255, blue: 35/255, alpha: 1)
                          : UIColor(red: 239/255, green: 239/255, blue: 237/255, alpha: 1)
        web.backgroundColor = paper
        web.scrollView.backgroundColor = paper
        session.appearancePayload = ["night": night, "safeTop": safeTop, "safeBottom": safeBottom]
        session.emit("appearance", session.appearancePayload)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: EmbroideryAssets) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "embroidery")
        view.stopLoading(); coordinator.cancelAll()
    }
}

/// Read-only, allowlisted scheme. Cached assets share the HTML origin so canvas exports remain untainted.
private final class EmbroideryAssets: NSObject, WKURLSchemeHandler {
    private var active: [ObjectIdentifier: URLSessionDataTask] = [:]
    private var stopped = Set<ObjectIdentifier>()
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("embroidery", isDirectory: true)
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask); stopped.insert(id); active.removeValue(forKey: id)?.cancel()
    }
    func cancelAll() { stopped.formUnion(active.keys); for task in active.values { task.cancel() }; active.removeAll() }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task); stopped.remove(id)
        guard let url = task.request.url, url.host == "local" else { fail(task); return }
        let path = url.path.removingPercentEncoding ?? url.path
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.isEmpty else { fail(task); return }
        let name = parts.last!
        var mime: String
        switch (name as NSString).pathExtension.lowercased() {
        case "html": mime = "text/html"
        case "js": mime = "application/javascript"
        case "json": mime = "application/json"
        case "png": mime = "image/png"
        case "svg": mime = "image/svg+xml"   // 1012 搜来的图标
        case "ttf": mime = "font/ttf"
        default: mime = "text/plain"
        }
        if parts.first == "workpng" { mime = "image/png" }
        var remote: URL?
        if parts.first == "font", parts.count == 2 {
            if let local = Bundle.main.url(forResource: (name as NSString).deletingPathExtension, withExtension: "ttf"),
               let data = try? Data(contentsOf: local) { finish(task, data, mime); return }
            let fontDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("kakao_fonts").appendingPathComponent(name)
            if let data = try? Data(contentsOf: fontDir) { finish(task, data, mime); return }
            let allowed = ["linshiai-1.ttf", "yuhe.ttf", "huoxuai.ttf", "jianxue.ttf", "chaoyong.ttf", "neozhisong.ttf", "silkscreen.ttf", "jbmono.ttf"]
            guard allowed.contains(name) else { fail(task); return }
            remote = AlcoveAPI.fullURL("/api/kakao/fonts/" + name)
        } else if parts.first == "workpng", parts.count == 2,
                  name.range(of: "^emb_[A-Za-z0-9_-]+$", options: .regularExpression) != nil {
            remote = AlcoveAPI.fullURL("/api/pulse-range/embroidery/png/" + name)
        } else if parts.first == "data", parts.count >= 2 {
            remote = AlcoveAPI.fullURL("/api/pulse-range/embroidery" + path)
        } else if parts.count == 1, ["embroidery.html", "geometry.js", "glyphs.js", "render.js", "editor.js", "finish.js", "opentype.min.js", "fonts.json"].contains(name),
                  let local = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Embroidery"),
                  let data = try? Data(contentsOf: local) { finish(task, data, mime); return }
        guard let remote else { fail(task); return }
        let cached = cache.appendingPathComponent(parts.joined(separator: "/"))
        if let data = try? Data(contentsOf: cached) { finish(task, data, mime); return }
        let download = AlcoveAPI.session.dataTask(with: remote) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, !self.stopped.contains(id) else { return }
                self.active.removeValue(forKey: id)
                guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    task.didFailWithError(error ?? NSError(domain: "EmbroideryAssets", code: 404)); return
                }
                do {
                    try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: cached, options: .atomic)
                } catch { /* Resource still displays; the next visit can retry caching. */ }
                self.finish(task, data, mime)
            }
        }
        active[id] = download; download.resume()
    }
    private func finish(_ task: WKURLSchemeTask, _ data: Data, _ mime: String) {
        guard let url = task.request.url else { fail(task); return }
        // fetch checks response.ok; a generic URLResponse has no HTTP success status.
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime + (mime.hasPrefix("text/") || mime.contains("json") || mime.contains("javascript") ? "; charset=utf-8" : ""),
                           "Content-Length": String(data.count), "Access-Control-Allow-Origin": "*"]) else { fail(task); return }
        task.didReceive(response)
        task.didReceive(data); task.didFinish()
    }
    private func fail(_ task: WKURLSchemeTask) { task.didFailWithError(NSError(domain: "EmbroideryAssets", code: 404)) }
}

// Full-screen house destination uses the same editor and asks the main window for safe areas.
struct EmbroideryRoom: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shown = true
    var body: some View {
        EmbroideryView(isPresented: $shown, startFull: true)
            .onChange(of: shown) { value in if !value { dismiss() } }
    }
}

struct EmbroideryCard: Decodable {
    let id: String
    let author: String
    let date: String
    let image: String
    let title: String?
}

struct EmbroideryMessageCard: View {
    let card: EmbroideryCard
    @State private var opened = false
    @State private var replay = false
    @AppStorage(AlcoveAppearance.key) private var appearance = "light"
    var body: some View {
        let _ = appearance
        VStack(alignment: .leading, spacing: 6) {
            Button { replay = false; opened = true } label: {
                AsyncImage(url: AlcoveAPI.attachmentURL(card.image)) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else if phase.error != nil { Text("图片暂未载入，点开查看").font(.caption).frame(height: 100) }
                    else { ProgressView().frame(height: 100) }
                }
                .frame(maxWidth: 280)
            }.buttonStyle(.plain)
            HStack(spacing: 12) {
                Text((card.author == "jing" ? "陈璟" : "陈霁") + " · " + String(card.date.prefix(10)))
                    .font(.system(size: 11, design: .serif))
                Button { replay = true; opened = true } label: {
                    Label("看它绣出来", systemImage: "play").font(.system(size: 11))
                        .frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
        .foregroundColor(AlcoveAppearance.isDark ? Color.white.opacity(0.8) : Color.black.opacity(0.75))
        .fullScreenCover(isPresented: $opened) {
            EmbroideryView(isPresented: $opened, startFull: true, workID: card.id, replay: replay)
        }
    }
}
