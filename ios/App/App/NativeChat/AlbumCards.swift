import SwiftUI

struct AlbumSelection: Identifiable {
    let id = UUID()
    let photos: [AlbumPhoto]
    let selectedId: String
}

struct AlbumSavedMessageCard: View {
    let batch: AlbumSavedBatch
    let theme: AlcoveTheme
    @State private var opened = false

    var body: some View {
        Button { opened = true } label: {
            HStack(spacing: 11) {
                AlbumThumbnail(photo: batch.photos[0])
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(batch.summary).font(.system(size: 13, weight: .medium)).lineLimit(3)
                    HStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("收进相册")
                    }.font(.system(size: 10)).foregroundStyle(theme.textDim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.textDim)
            }
            .foregroundStyle(theme.text)
            .padding(11)
            .frame(maxWidth: 280, alignment: .leading)
            .background(theme.glassTint.opacity(theme.isDark ? 0.45 : 0.75),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.glassBorder, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(batch.summary + "，查看照片和备注")
        .fullScreenCover(isPresented: $opened) {
            AlbumBatchCard(batch: batch, theme: theme)
                .presentationBackground(.clear)
        }
    }
}

// The saved batch is immutable and ordered by the backend, never inferred from
// timestamps. The small event snapshot remains available in chat history offline.
private struct AlbumBatchCard: View {
    let batch: AlbumSavedBatch
    let theme: AlcoveTheme
    @Environment(\.dismiss) private var dismiss
    @State private var selected: AlbumSelection?
    @State private var selectedId: String?
    private var focused: AlbumPhoto { batch.photos.first { $0.id == selectedId } ?? batch.photos[0] }

    var body: some View {
        GeometryReader { geometry in
            let side = max(1, min(geometry.size.width - 32, geometry.size.height - 40, 440))
            ZStack {
                Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    .overlay(Color.black.opacity(0.24).ignoresSafeArea())
                    .onTapGesture { dismiss() }
                VStack(spacing: 0) {
                    HStack {
                        Label("\(batch.photos.count) 张珍藏", systemImage: "photo.stack")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.textDim)
                        Spacer()
                        // 0913 她报：点右上角 x 关不掉，反而进了大图。默认 button style 在新系统上
                        // 会把它渲染成比 32×32 更大的玻璃圆，点到圆的下缘就漏到下面的 mosaic 上去了。
                        // 钉死 .plain + contentShape 让看到的圆就是能点的圆，header 再抬一层 zIndex。
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                                .frame(width: 32, height: 32).background(theme.text.opacity(0.06), in: Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭收藏卡片")
                    }.padding(.horizontal, 17).padding(.top, 10).padding(.bottom, 8).zIndex(1)
                    AlbumBatchMosaic(photos: batch.photos) { photo in
                        selectedId = photo.id
                        selected = AlbumSelection(photos: batch.photos, selectedId: photo.id)
                    }
                    .frame(height: side * 0.58)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    // clipShape 只裁画面不裁点击区，这里显式把命中形状也收进圆角框里
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .padding(.horizontal, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(focused.category).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.textDim)
                            Text(batch.caption?.isEmpty == false ? batch.caption! : focused.note)
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.horizontal, 19).padding(.vertical, 13)
                    }
                }
                .frame(width: side, height: side)
                .foregroundStyle(theme.text)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.18), radius: 35, y: 15)
                .accessibilityAddTraits(.isModal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .fullScreenCover(item: $selected) { selection in AlbumPhotoViewer(selection: selection) }
    }
}

private struct AlbumBatchMosaic: View {
    let photos: [AlbumPhoto]
    let open: (AlbumPhoto) -> Void
    var body: some View {
        GeometryReader { geometry in
            if let first = photos.first {
                if photos.count == 1 {
                    tile(first).frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    HStack(spacing: 5) {
                        tile(first).frame(width: (geometry.size.width - 5) * 0.66)
                        VStack(spacing: 5) {
                            ForEach(Array(photos.dropFirst().prefix(3).enumerated()), id: \.element.id) { index, photo in
                                tile(photo)
                                    .overlay {
                                        if index == 2 && photos.count > 4 {
                                            Text("+\(photos.count - 4)").font(.title3.bold()).foregroundStyle(.white)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .background(.black.opacity(0.3)).allowsHitTesting(false)
                                        }
                                    }
                            }
                        }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
    }
    private func tile(_ photo: AlbumPhoto) -> some View {
        Button { open(photo) } label: { AlbumThumbnail(photo: photo) }
            .buttonStyle(.plain)
            .accessibilityLabel(photo.note.isEmpty ? "打开照片" : photo.note)
    }
}

struct AlbumPhotoViewer: View {
    let selection: AlbumSelection
    var editable = false
    var categories: [AlbumCategory] = []
    var changed: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [AlbumPhoto]
    @State private var selectedId: String
    @State private var editing: AlbumPhoto?

    init(selection: AlbumSelection, editable: Bool = false, categories: [AlbumCategory] = [], changed: @escaping () -> Void = {}) {
        self.selection = selection; self.editable = editable; self.categories = categories; self.changed = changed
        _photos = State(initialValue: selection.photos)
        _selectedId = State(initialValue: selection.selectedId)
    }
    private var current: AlbumPhoto? { photos.first { $0.id == selectedId } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                // 0913 同 AlbumBatchCard 的毛病：Image 撑到 44×44 只是占位，能点的还是图标那一小块，
                // 周围一圈是空的。contentShape 把整块方框都变成可点区域。
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("关闭照片")
                Spacer()
                Text("\((photos.firstIndex { $0.id == selectedId } ?? 0) + 1) / \(photos.count)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                Spacer()
                if editable {
                    Button { editing = current } label: { Image(systemName: "pencil").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("编辑照片备注和分类")
                } else { Color.clear.frame(width: 44, height: 44) }
            }.padding(.horizontal, 8)
            TabView(selection: $selectedId) {
                ForEach(photos) { photo in
                    AlbumZoomImage(photo: photo).tag(photo.id)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            if let current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(current.category)
                            Spacer()
                            Label(current.isPosted ? "已发过" : current.postStatus == "reserved" ? "正在用于发帖" : current.postStatus == "unused" ? "未发过" : "", systemImage: current.isPosted ? "checkmark.circle" : "circle")
                        }.font(.caption).foregroundStyle(.white.opacity(0.6))
                        if !current.note.isEmpty { Text(current.note).font(.system(size: 16)).lineSpacing(5) }
                        if let date = current.createdAt { Text(albumDate(date)).font(.caption2).foregroundStyle(.white.opacity(0.45)) }
                        ForEach(current.posts ?? [], id: \.postId) { post in
                            if let raw = post.url, let url = AlbumAPI.imageURL(raw) {
                                Link("查看帖子 · \(albumDate(post.publishedAt, time: true))", destination: url).font(.caption)
                            } else {
                                Text("发布于 \(albumDate(post.publishedAt, time: true))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
                }.frame(maxHeight: 180)
            }
        }
        .foregroundStyle(.white).background(.black).preferredColorScheme(.dark)
        .sheet(item: $editing) { photo in
            AlbumPhotoEditor(photo: photo, categories: categories) { updated in
                if let index = photos.firstIndex(where: { $0.id == updated.id }) { photos[index] = updated }
                changed()
            }
        }
    }
}

/// 0912 她要的：后端给的是 ISO 串（2026-07-13T04:00:00.000Z），显示成北京时间的正常日期；认不出就原样
private func albumDate(_ raw: String, time: Bool = false) -> String {
    guard let date = ISO8601DateFormatter.alcoveFrac.date(from: raw)
            ?? ISO8601DateFormatter.alcove.date(from: raw) else { return raw }
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    f.dateFormat = time ? "yyyy年M月d日 HH:mm" : "yyyy年M月d日"
    return f.string(from: date)
}

// Magnify within the current page; changing photos resets zoom automatically.
// 0912：看的是中图不是原图；中图没到之前垫着缩略图（图库里刚看过，多半秒出），
// 中图拉不到（比如后端还没重启）才退回原图。
private struct AlbumZoomImage: View {
    let photo: AlbumPhoto
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var useOriginal = false
    var body: some View {
        GeometryReader { geometry in
            CachedPhaseImage(url: useOriginal ? photo.original : photo.view) { phase in
                ZStack {
                    Color.black
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    case .empty:
                        AlbumRemoteImage(url: photo.thumbnail, fit: true)
                    case .failure:
                        if useOriginal {
                            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
                        } else {
                            AlbumRemoteImage(url: photo.thumbnail, fit: true)
                                .onAppear { useOriginal = true }
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.id(useOriginal)
        }.clipped()
            .scaleEffect(scale).clipped()
            .gesture(MagnifyGesture().onChanged { value in
                scale = min(max(baseScale * value.magnification, 1), 4)
            }.onEnded { _ in baseScale = scale })
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) { scale = scale > 1 ? 1 : 2; baseScale = scale }
            }
            .onDisappear { scale = 1; baseScale = 1 }
            .accessibilityLabel("照片，双击或双指缩放")
    }
}

private struct AlbumPhotoEditor: View {
    let photo: AlbumPhoto
    @State var categories: [AlbumCategory]
    let saved: (AlbumPhoto) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var category: String?
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("留给这张照片的话") { TextField("一句话", text: $caption, axis: .vertical).lineLimit(3...8) }
                Section {
                    Picker("相簿", selection: $category) {
                        Text("未分类").tag(String?.none)
                        ForEach(categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .disabled(saving)
            .navigationTitle("编辑照片").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中" : "完成") {
                        saving = true; error = nil
                        Task {
                            defer { saving = false }
                            do {
                                let updated = try await AlbumAPI.edit(photo, caption: caption, category: category)
                                saved(updated); dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(saving || caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(saving)
            .task {
                caption = photo.note; category = photo.categoryId
                if let id = photo.categoryId, !categories.contains(where: { $0.id == id }) {
                    categories.append(AlbumCategory(categoryId: id, name: photo.category))
                }
                do { categories = try await AlbumAPI.categories() }
                catch { self.error = "分类暂时无法刷新，可以稍后再试。" }
            }
        }
    }
}
