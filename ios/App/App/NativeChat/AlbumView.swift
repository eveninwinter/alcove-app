import SwiftUI
import PhotosUI
import ImageIO

struct NativeAlbumView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("alcoveTheme") private var themeName = "haven"
    @StateObject private var store = AlbumStore()
    @State private var tab = 0
    @State private var showUpload = false
    @State private var selected: AlbumSelection?
    @State private var editingCategory: AlbumCategory?
    @State private var categoryName = ""
    @State private var showCategoryName = false
    @State private var categoryBusy = false
    @State private var actionError: String?
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = ""   // 全屋黑夜开关，拨了要重画
    // 0928 她又报黑夜下相册白底白字：named("kakao") 恒报白天，字却是包的颜色。Kakao 下改用面板那套（跟全屋开关走）
    private var theme: AlcoveTheme {
        _ = houseAppearance
        return AlcoveAppearance.chatOnly(themeName) ? .panelNamed(themeName) : .named(themeName)
    }
    private var title: String {
        if let id = store.category { return store.categories.first { $0.id == id }?.name ?? "相簿" }
        return tab == 0 ? "照片" : "相簿"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if tab == 1 && store.category == nil { categoryGrid } else { library }
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $store.search, prompt: "搜索照片、备注")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if store.category != nil { store.category = nil } else { dismiss() } } label: {
                        Image(systemName: "chevron.left")
                    }.accessibilityLabel(store.category == nil ? "返回聊天" : "返回相簿")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if tab == 1 {
                        Button {
                            editingCategory = nil; categoryName = ""; showCategoryName = true
                        } label: { Image(systemName: "folder.badge.plus") }
                        .disabled(categoryBusy)
                        .accessibilityLabel("新建相簿")
                    }
                    Button { showUpload = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加照片")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .refreshable { await store.loadCategories(); await store.reload() }
            .task { await store.loadCategories() }
            .task(id: store.queryKey) {
                // Debounce typing and cancel obsolete searches before they can overwrite a newer page.
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                await store.reload()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.loadCategories(); await store.reload() } }
            }
            .onChange(of: store.search) { _, value in if !value.isEmpty { tab = 0 } }
            .sheet(isPresented: $showUpload) {
                AlbumUploadView(categories: store.categories, initialCategory: store.category) {
                    Task { await store.loadCategories(); await store.reload() }
                }
            }
            .fullScreenCover(item: $selected) { selection in
                AlbumPhotoViewer(selection: selection, editable: true, categories: store.categories) {
                    Task { await store.loadCategories(); await store.reload() }
                }
            }
            .alert(editingCategory == nil ? "新建相簿" : "相簿名称", isPresented: $showCategoryName) {
                TextField("名称", text: $categoryName)
                Button("取消", role: .cancel) {}
                Button("保存") { saveCategory() }
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("没能保存", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("好", role: .cancel) { actionError = nil }
            } message: { Text(actionError ?? "") }
        }
        .tint(theme.text)
        .preferredColorScheme(AlcoveAppearance.isDark ? .dark : .light)   // 0928：只认全屋黑白开关
    }

    private var bottomBar: some View {
        HStack(spacing: 50) {
            tabButton("图库", icon: "photo.stack", value: 0)
            tabButton("相簿", icon: "rectangle.stack", value: 1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(.regularMaterial)
    }

    private func tabButton(_ label: String, icon: String, value: Int) -> some View {
        Button {
            tab = value; store.category = nil; store.search = ""
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab == value ? icon + ".fill" : icon).font(.system(size: 21))
                Text(label).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tab == value ? theme.text : theme.textDim)
            .frame(width: 66)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("全部", "all")
                    filterChip("我添加的", "user")
                    filterChip("他添加的", "assistant")
                    filterChip("聊天收藏", "chat_saved")
                    filterChip("未发过", "unused")
                    filterChip("已发过", "posted")
                }.padding(.horizontal, 20)
            }
            if store.loading && store.photos.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 90)
            } else if store.photos.isEmpty, let error = store.error {
                AlbumEmptyState(icon: "wifi.exclamationmark", title: "暂时打不开相册", detail: error) {
                    Task { await store.reload() }
                }
            } else if store.photos.isEmpty {
                AlbumEmptyState(icon: "photo.on.rectangle.angled", title: "这里还没有照片",
                                detail: store.search.isEmpty ? "把想留住的照片放进来。" : "试试别的关键词。", retry: nil)
            } else {
                Text(store.hasMore ? "\(store.photos.count) 张照片 · 继续下滑查看更多" : "\(store.photos.count) 张照片")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(store.photos) { photo in
                        Button { selected = AlbumSelection(photos: store.photos, selectedId: photo.id) } label: {
                            AlbumThumbnail(photo: photo)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(alignment: .bottomTrailing) {
                                    if photo.isPosted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(5).background(.black.opacity(0.35), in: Capsule()).padding(5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(photo.note.isEmpty ? "照片" : photo.note)，\(photo.category)\(photo.isPosted ? "，已发过" : "")")
                    }
                }
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
                if store.hasMore {
                    Button { Task { await store.more() } } label: {
                        HStack { if store.loading { ProgressView() }; Text(store.loading ? "正在加载" : "加载更多") }
                            .frame(maxWidth: .infinity).padding()
                    }
                    .disabled(store.loading)
                    .onAppear { if store.error == nil { Task { await store.more() } } }
                }
            }
        }
    }

    private func filterChip(_ label: String, _ value: String) -> some View {
        Button { store.filter = value } label: {
            Text(label).font(.system(size: 13, weight: store.filter == value ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(store.filter == value ? Color(uiColor: .systemBackground) : theme.text)
                .background(store.filter == value ? theme.text : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }.buttonStyle(.plain)
        .accessibilityAddTraits(store.filter == value ? .isSelected : [])
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("我的相簿").font(.title3.bold()).padding(.horizontal, 20)
            if let error = store.categoryError {
                AlbumEmptyState(icon: "wifi.exclamationmark", title: "相簿暂时无法加载", detail: error) {
                    Task { await store.loadCategories() }
                }
            } else if store.categories.isEmpty {
                AlbumEmptyState(icon: "rectangle.stack.badge.plus", title: "给照片一个位置", detail: "点右上角，新建你的第一个相簿。", retry: nil)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 24) {
                ForEach(store.categories) { category in
                    Button { store.category = category.id; store.filter = "all" } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            AlbumRemoteImage(url: category.coverUrl.flatMap(AlbumAPI.imageURL))
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Text(category.name).font(.system(size: 16, weight: .medium)).lineLimit(1)
                            Text("\(category.count ?? 0) 张").font(.footnote).foregroundStyle(.secondary)
                        }.foregroundStyle(theme.text)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("重命名", systemImage: "pencil") {
                            editingCategory = category; categoryName = category.name; showCategoryName = true
                        }
                    }
                }
            }.padding(.horizontal, 20)
        }
    }

    private func saveCategory() {
        let name = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !categoryBusy else { return }
        let id = editingCategory?.id
        categoryBusy = true
        Task {
            defer { categoryBusy = false }
            do { _ = try await AlbumAPI.category(name: name, id: id); await store.loadCategories() }
            catch { actionError = error.localizedDescription }
        }
    }
}

struct AlbumEmptyState: View {
    let icon: String
    let title: String
    let detail: String
    var retry: (() -> Void)?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let retry { Button("重试", action: retry).buttonStyle(.bordered).padding(.top, 3) }
        }.frame(maxWidth: .infinity).padding(.horizontal, 30).padding(.vertical, 70)
    }
}

// GeometryReader bounds the fill image, so portrait assets cannot stretch grid cells.
struct AlbumRemoteImage: View {
    let url: URL?
    var fit = false
    var body: some View {
        GeometryReader { geometry in
            CachedPhaseImage(url: url) { phase in
                ZStack {
                    (fit ? Color.black : Color(uiColor: .secondarySystemBackground))
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    case .empty:
                        if url != nil { ProgressView() } else { Image(systemName: "photo").foregroundStyle(.secondary) }
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.id(url)
        }.clipped()
    }
}

struct AlbumThumbnail: View {
    let photo: AlbumPhoto
    var body: some View { AlbumRemoteImage(url: photo.thumbnail) }
}

private struct AlbumUploadView: View {
    @Environment(\.dismiss) private var dismiss
    @State var categories: [AlbumCategory]
    let initialCategory: String?
    let saved: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var preview: UIImage?
    @State private var caption = ""
    @State private var category: String?
    @State private var requestId = UUID().uuidString
    @State private var preparing = false
    @State private var saving = false
    @State private var error: String?
    @State private var categoriesFailed = false
    @State private var attempted = false
    @State private var showNewCategory = false
    @State private var newCategoryName = ""
    @State private var categorySaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                        Group {
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 280)
                            } else {
                                VStack(spacing: 12) {
                                    if preparing { ProgressView() } else { Image(systemName: "photo.badge.plus").font(.largeTitle) }
                                    Text(preparing ? "正在读取照片" : "选择一张照片")
                                }.frame(maxWidth: .infinity).padding(.vertical, 40)
                            }
                        }
                    }.disabled(saving || attempted)
                    TextField("为这张照片留一句话", text: $caption, axis: .vertical)
                        .lineLimit(2...5).disabled(saving || attempted)
                }
                Section("放进相簿") {
                    Picker("分类", selection: $category) {
                        Text("未分类").tag(String?.none)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }.disabled(saving || attempted)
                    Button("新建相簿", systemImage: "folder.badge.plus") { showNewCategory = true }
                        .disabled(saving || attempted || categorySaving)
                    if categoriesFailed {
                        Button("分类加载失败，点此重试") { Task { await reloadCategories() } }
                    }
                }
                Section {
                    Text("直接放进相册，留待以后翻看。不会发到聊天里。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        if attempted {
                            Text("重试会继续确认这次保存，不会重复添加。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("添加照片").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button { upload() } label: {
                        if saving { ProgressView() } else { Text(attempted ? "重试" : "保存") }
                    }.disabled(saving || preparing || categorySaving || imageData == nil || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
            .task { category = initialCategory; await reloadCategories() }
            .task(id: item) { await prepareImage() }
            .alert("新建相簿", isPresented: $showNewCategory) {
                TextField("名称", text: $newCategoryName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    categorySaving = true
                    Task {
                        defer { categorySaving = false }
                        do {
                            let created = try await AlbumAPI.category(name: name)
                            categories.removeAll { $0.id == created.id }; categories.append(created)
                            category = created.id; newCategoryName = ""
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func reloadCategories() async {
        do { categories = try await AlbumAPI.categories(); categoriesFailed = false }
        catch { categoriesFailed = true }
    }

    private func prepareImage() async {
        guard let item else { return }
        preparing = true; error = nil; imageData = nil; preview = nil
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { throw AlbumError.invalidImage }
            // Bound decoded pixels off the main thread (large HEICs can otherwise stall the composer).
            let jpeg = await Task.detached(priority: .userInitiated) { () -> Data? in
                guard let source = CGImageSourceCreateWithData(raw as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: cg).jpegData(compressionQuality: 0.9)
            }.value
            guard !Task.isCancelled else { return }
            guard let jpeg, let image = UIImage(data: jpeg) else { throw AlbumError.invalidImage }
            imageData = jpeg; preview = image; requestId = UUID().uuidString
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        if !Task.isCancelled { preparing = false }
    }

    private func upload() {
        guard let imageData, !saving else { return }
        saving = true; error = nil; attempted = true
        Task {
            defer { saving = false }
            do {
                _ = try await AlbumAPI.upload(data: imageData, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines), category: category, requestId: requestId)
                saved(); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
