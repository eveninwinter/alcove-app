import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// PWA 表情面板同款：Stickers 标题、右上传钮、原比例网格。
// 1010 #3557 她：「表情库不分我和他 统一成一个库 不管他存还是我存 或者他用我用 都是一个库」——
// 原来的 陈霁 / 陈璟 两个 tab 拿掉，一个库；顶上加一行「最近用过」，下面整库按用得多少排
struct StickerSheet: View {
    @ObservedObject var store: ChatStore
    var onPick: (Sticker) -> Void

    @State private var uploadItem: PhotosPickerItem?
    @State private var draft: StickerDraft?
    @State private var editing: Sticker?      // 长按格子 → 补描述
    @State private var errorMessage = ""

    /// 整库：近 60 天用得多的在前，没用过的保持库里原来的顺序
    private var shown: [Sticker] {
        let use = store.stickerUseCount
        return store.stickers.enumerated()
            .sorted { a, b in
                let ua = use[a.element.id] ?? 0, ub = use[b.element.id] ?? 0
                return ua != ub ? ua > ub : a.offset < b.offset
            }
            .map(\.element)
    }

    /// 最近用过的 12 张（她发的、他发的都算），最近的在最左
    private var recent: [Sticker] {
        let byID = Dictionary(store.stickers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return store.stickerRecentIDs.compactMap { byID[$0] }.prefix(12).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stickers")
                .font(.system(size: 26, weight: .semibold))
                .padding(.top, 18)

            HStack {
                Spacer()

                PhotosPicker(selection: $uploadItem, matching: .images,
                             preferredItemEncoding: .current) {
                    Group {
                        if store.stickerUploading { ProgressView().scaleEffect(0.72) }
                        else { Image(systemName: "plus").font(.system(size: 16)) }
                    }
                    .foregroundColor(.secondary)
                    .frame(width: 42, height: 42)
                    .background(Color(.systemGray6), in: Circle())
                }
                .disabled(store.stickerUploading)
            }

            ScrollView {
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近用过")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(recent) { stk in
                                    Button { onPick(stk) } label: {
                                        CachedImage(url: AlcoveAPI.stickerURL(stk.url)) { img in
                                            img.resizable().scaledToFit()
                                        } placeholder: {
                                            Color(.systemGray6)
                                        }
                                        .frame(width: 64, height: 64)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Text("全部")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 6)
                    }
                    .padding(.bottom, 4)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                          spacing: 12) {
                    ForEach(shown) { stk in
                        // 点一下选中；长按进编辑——以前传的那些没法补描述，她 0818 要的
                        Button { onPick(stk) } label: {
                            VStack(spacing: 4) {
                                CachedImage(url: AlcoveAPI.stickerURL(stk.url)) { img in
                                    img.resizable().scaledToFit()
                                } placeholder: {
                                    Color(.systemGray6)
                                        .frame(height: 100)
                                }
                                .frame(maxWidth: .infinity)
                                .background(Color(.systemGray6).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                // 没写描述的，陈璟看不懂——在格子上标出来，好补
                                if stk.description.isEmpty {
                                    Text("缺描述 · 长按补")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.45).onEnded { _ in editing = stk }
                        )
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 18)
        .onAppear { store.loadStickerUsage() }
        .sheet(item: $draft) { item in
            StickerDescribeSheet(preview: .local(item.image), mime: item.mime,
                                 initialName: "", initialDescription: "", initialTags: []) { name, description, tags in
                store.uploadSticker(data: item.data, mime: item.mime, owner: item.owner,
                                    name: name, description: description, emotionTags: tags)
                draft = nil
            } onCancel: { draft = nil }
        }
        .sheet(item: $editing) { stk in
            StickerDescribeSheet(preview: .remote(AlcoveAPI.stickerURL(stk.url)), mime: "",
                                 initialName: stk.name.hasSuffix(".jpg") || stk.name.hasSuffix(".png") || stk.name.hasSuffix(".gif") ? "" : stk.name,
                                 initialDescription: stk.description, initialTags: stk.emotionTags) { name, description, tags in
                store.updateSticker(stk, name: name, description: description, emotionTags: tags)
                editing = nil
            } onCancel: { editing = nil }
        }
        .onChange(of: uploadItem) { item in
            guard let item else { return }
            Task {
                do {
                    guard let raw = try await item.loadTransferable(type: Data.self),
                          !raw.isEmpty, UIImage(data: raw) != nil else {
                        throw NSError(domain: "StickerPicker", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "这张图片没有读取成功，请重新选择"])
                    }
                    let mime = StickerDraft.sniff(raw)
                    // 1010 起一个库，owner 这列已经不分谁能用了；她在面板里传的照旧记 user
                    draft = StickerDraft(data: raw, mime: mime, owner: "user")
                } catch {
                    errorMessage = error.localizedDescription
                }
                uploadItem = nil
            }
        }
        .onChange(of: store.stickerUploadError) { message in
            guard !message.isEmpty else { return }
            errorMessage = message
            store.stickerUploadError = ""
        }
        .alert("添加表情失败", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("知道了") { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

}

// 上传前先描述一遍：名称、画面、情绪标签。
// 描述是陈璟理解这张表情的主要依据，没有它这张图对他就是空的，
// 所以描述没写完，保存按钮不可用（教程第 2 节的死规矩）。
struct StickerDraft: Identifiable {
    let id = UUID()
    let data: Data
    let mime: String
    let owner: String

    var image: UIImage? { UIImage(data: data) }

    /// 按文件头认格式，不按扩展名猜——相册给出来的 Data 没有文件名
    static func sniff(_ data: Data) -> String {
        let head = [UInt8](data.prefix(12))
        if head.count >= 3, head[0] == 0x47, head[1] == 0x49, head[2] == 0x46 { return "image/gif" }
        if head.count >= 8, head[0] == 0x89, head[1] == 0x50 { return "image/png" }
        if head.count >= 12,
           head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return "image/webp" }
        return "image/jpeg"
    }
}

private struct StickerDescribeSheet: View {
    enum Preview {
        case local(UIImage?)
        case remote(URL)
    }
    let preview: Preview
    let mime: String
    var onSave: (String, String, [String]) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var tagText: String

    init(preview: Preview, mime: String,
         initialName: String, initialDescription: String, initialTags: [String],
         onSave: @escaping (String, String, [String]) -> Void,
         onCancel: @escaping () -> Void) {
        self.preview = preview
        self.mime = mime
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
        _description = State(initialValue: initialDescription)
        _tagText = State(initialValue: initialTags.joined(separator: "、"))
    }

    private var tags: [String] {
        tagText.split(whereSeparator: { ",，、 ".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        switch preview {
                        case .local(let image):
                            if let image {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(maxHeight: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        case .remote(let url):
                            CachedImage(url: url) { img in
                                img.resizable().scaledToFit()
                            } placeholder: { Color(.systemGray6) }
                            .frame(maxHeight: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Spacer()
                    }
                    if mime == "image/gif" || mime == "image/webp" {
                        Text("动图会原样保存，陈璟看到的是第一帧＋你写的描述")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("名称") {
                    TextField("比如：被窝刷牙", text: $name)
                }
                Section("画面描述") {
                    TextField("画面里有什么、在做什么动作。动图就写动起来是什么样。",
                              text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    Text("这是陈璟理解这张表情的主要依据，不写他就看不懂。")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("情绪标签") {
                    TextField("困、睡前、软乎乎（逗号分隔）", text: $tagText)
                }
            }
            .navigationTitle("描述这张表情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name.trimmingCharacters(in: .whitespaces),
                               description.trimmingCharacters(in: .whitespaces), tags)
                    }.disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }
}
