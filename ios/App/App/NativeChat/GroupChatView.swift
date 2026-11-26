import SwiftUI

// 1126 #6134 群聊：只有陈霁、陈璟、隅三个人，不用艾特，谁说的另外两个都看得见（后台 group_room.py，/api/group/*）。
// 她定的：整体布局和遮罩直接套主聊天 Kakao 那套（壁纸同一张、顶部渐隐、底部系统 soft 模糊），顶上是她自己能改的群名。
// 气泡、顶栏左右按钮、打字框她要自己改，这里只放能用的最简占位，不做样式。

struct GroupRecord: Identifiable, Equatable {
    let id: Int
    let ts: String
    let who: String       // ji / jing / yu
    let name: String
    let text: String
    let attachmentURL: String?

    var isMine: Bool { who == "ji" }
}

@MainActor
final class GroupChatStore: ObservableObject {
    @Published var records: [GroupRecord] = []
    @Published var name = "三心一意"
    @Published var sending = false
    private var timer: Task<Void, Never>?

    func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() { timer?.cancel(); timer = nil }

    func poll() async {
        let since = records.last?.id ?? 0
        guard let obj = try? await AlcoveAPI.getRaw("/api/group/poll?since=\(since)") else { return }
        if let n = obj["name"] as? String, !n.isEmpty, n != name { name = n }
        let rows = (obj["records"] as? [[String: Any]] ?? []).compactMap { r -> GroupRecord? in
            guard let id = r["id"] as? Int else { return nil }
            return GroupRecord(id: id, ts: r["ts"] as? String ?? "", who: r["who"] as? String ?? "",
                               name: r["name"] as? String ?? "", text: r["text"] as? String ?? "",
                               attachmentURL: r["attachment_url"] as? String)
        }
        let known = Set(records.map(\.id))
        let fresh = rows.filter { !known.contains($0.id) }
        if !fresh.isEmpty { records.append(contentsOf: fresh) }
    }

    func send(_ text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        sending = true
        defer { sending = false }
        guard let obj = try? await AlcoveAPI.postRaw("/api/group/send", body: ["who": "ji", "text": t]),
              obj["ok"] as? Bool == true else { return false }
        await poll()
        return true
    }

    func rename(_ newName: String) async {
        let n = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        if let obj = try? await AlcoveAPI.postRaw("/api/group/name", body: ["name": n]),
           let saved = obj["name"] as? String {
            name = saved
        }
    }
}

struct GroupChatView: View {
    let onDismiss: () -> Void
    @StateObject private var store = GroupChatStore()
    @ObservedObject private var wall = ChatWallpaperStore.shared
    @ObservedObject private var kakaoPacks = KakaoPackStore.shared
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @AppStorage("chatFontSize") private var chatFontSize = 14
    @State private var draft = ""
    @State private var renaming = false
    @State private var nameDraft = ""
    @FocusState private var focused: Bool

    private var theme: AlcoveTheme { .named(themeName) }

    var body: some View {
        ZStack {
            // 壁纸跟主聊天同一张（她换过的优先，没换就是主题包的）
            ChatWallpaperRenderer(descriptor: wall.descriptor)
                .ignoresSafeArea()
            messageList
        }
        .foregroundColor(theme.text)
        .onAppear { store.start() }
        .onDisappear { store.stop() }
        .alert("改群名", isPresented: $renaming) {
            TextField("群名", text: $nameDraft)
            Button("取消", role: .cancel) {}
            Button("好") { Task { await store.rename(nameDraft) } }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.records) { r in
                        row(r).id(r.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.records.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
            }
            // 跟主聊天 Kakao 一样：遮罩只罩列表本体、只罩顶部那一截（顶栏 44 留空，再接 60 渐隐）
            .mask(topOnlyFadeMask.ignoresSafeArea())
            .safeAreaBar(edge: .top, spacing: 0) {
                header.frame(height: 44, alignment: .top)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                inputBar
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .scrollEdgeEffectHidden(true, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focused = false }
        }
    }

    // 顶栏：中间是她能改的群名（点一下改）。左右按钮她要自己改，左边先只放一个能退出去的返回，右边空着
    private var header: some View {
        ZStack {
            Button {
                nameDraft = store.name
                renaming = true
            } label: {
                Text(store.name)
                    .font(kakaoPacks.fontName.map { Font.custom($0, fixedSize: CGFloat(chatFontSize)) }
                          ?? .system(size: CGFloat(chatFontSize), weight: .semibold))
                    .foregroundColor(theme.text)
                    .lineLimit(1)
                    .frame(minWidth: 150, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(theme.textDim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    // 气泡她要自己改：占位只有名字和字，她的靠右，他们俩的靠左
    private func row(_ r: GroupRecord) -> some View {
        VStack(alignment: r.isMine ? .trailing : .leading, spacing: 3) {
            if !r.isMine {
                Text(r.name).font(.system(size: 12)).foregroundColor(theme.textDim)
            }
            Text(r.text.isEmpty ? (r.attachmentURL == nil ? "" : "[图片]") : r.text)
                .font(.system(size: CGFloat(chatFontSize)))
                .multilineTextAlignment(r.isMine ? .trailing : .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: r.isMine ? .trailing : .leading)
    }

    // 打字框她要自己改：占位就一行字加一个发送
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("信息", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .font(.system(size: CGFloat(chatFontSize)))
            Button("发送") {
                let text = draft
                draft = ""
                Task { if !(await store.send(text)) { draft = text } }
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.sending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// 照抄 ChatView.topOnlyFadeMask（Kakao 那份）：顶栏那段留空，再接 60 的渐隐，底下全亮
    private var topOnlyFadeMask: some View {
        let chromeTop = Self.topSafeInset + 44
        return VStack(spacing: 0) {
            Color.clear.frame(height: chromeTop)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.35),
                    .init(color: .black.opacity(0.7), location: 0.65),
                    .init(color: .black, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            Color.black
        }
    }

    private static var topSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.top ?? 59
    }
}
