import SwiftUI

// 出厂设置（2026-08-19 她要的面板）。
//
// 她原话：「我还想加一个我能直接改心跳prompt的面板，直接连接后端的改完自动重启。
// 这样不用老麻烦你了哦！」后来又补：「你的claude.md、output style、hook我是不是
// 也都能让你做个前端我自己改」「memory里我也能改吗」。
//
// 能改的只有白名单里那些纯文本：心跳文案、说话方式、情书、开窗喂的几份、memory。
// stop hook 不进来（她定的）——那是他说话的通道，剪错一刀就哑了。
//
// 每次存之前后端自动留一份带时间戳的旧版，右上角能翻回去。存完按文件跑生效动作：
// 心跳文案 → 重启心跳；说话方式 → 重拼 output style；情书 → cp 成 CLAUDE.md。

private struct FactoryFile: Identifiable {
    var id: String { key + "/" + name }
    let key: String
    let name: String
    let title: String
    let desc: String
    let chars: Int
    let at: String

    init(_ raw: [String: Any]) {
        key = raw.string("key")
        name = raw.string("name")
        title = raw.string("title")
        desc = raw.string("desc")
        chars = raw.int("chars")
        at = raw.string("at")
    }
}

private struct FactoryGroup: Identifiable {
    var id: String { group }
    let group: String
    let items: [FactoryFile]
}

struct NativeFactoryView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("alcoveTheme") private var themeName = "haven"

    @State private var groups: [FactoryGroup] = []
    @State private var loading = true
    @State private var opened: FactoryFile?
    @State private var pendingDelete: FactoryFile?
    @State private var note = ""

    private var palette: GlassPalette { .named(themeName) }

    /// 1015 #3903 换成 Sanctus（她点头的 /root/workroom/mock/kit/factory.html 左边）：分组标题＋玻璃卡，一行一个文件
    private var safeTop: CGFloat { FloatingOverlay.appWindow()?.safeAreaInsets.top ?? 54 }

    private static func groupNote(_ group: String) -> String? {
        switch group {
        case "锚点": return "what he reads"
        case "记忆（主聊天）": return "what he keeps"
        case "API 房间": return "the other room"
        case "工作室": return "the workroom"
        case "记忆（工作室）": return "what I keep"
        default: return nil
        }
    }

    var body: some View {
        let ink = SanctusPageInk()
        ZStack {
            ink.page.ignoresSafeArea()
            VStack(spacing: 0) {
                SanctusTopBar(title: "出厂设置", onBack: { dismiss() }) { EmptyView() }
                    .padding(.top, safeTop)
                if loading {
                    Spacer(); ProgressView().tint(ink.sub); Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text(note.isEmpty ? "改坏了最多他说话变怪，右上角能翻回上一版。记忆那些长按能删" : note)
                                .font(SanctusPageFont.cn(11))
                                .foregroundColor(note.isEmpty ? ink.sub : ink.body)
                                .padding(.horizontal, 6).padding(.top, 4)
                            ForEach(groups) { g in
                                SanctusSection(g.group, note: Self.groupNote(g.group))
                                SanctusGroup {
                                    ForEach(g.items) { f in
                                        row(f, ink)
                                            .onTapGesture { opened = f }
                                            .contextMenu {
                                                // memory 才给删，锚点少一份他就缺一块
                                                if f.key.hasPrefix("mem") && f.name.uppercased() != "MEMORY.MD" {
                                                    Button(role: .destructive) {
                                                        pendingDelete = f
                                                    } label: {
                                                        Label("删掉这条", systemImage: "trash")
                                                    }
                                                }
                                            }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .environment(\.sanctusInk, ink)
        .task { await load() }
        .confirmationDialog(
            pendingDelete.map { "删掉「\($0.title)」？" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删掉", role: .destructive) {
                if let f = pendingDelete { Task { await remove(f) } }
            }
            Button("算了", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("备份留着能捞回来，索引里那行指针也会一起清掉")
        }
        .sheet(item: $opened) { f in
            if f.key == "heartbeat" {
                // 心跳走专用的：整条 prompt 摆出来，代码算的锁住给她看，
                // 她写的那几段给她改（0819 她要的：「完整的不缺一个字的prompt」）
                PromptEditor(palette: palette) { Task { await load() } }
            } else {
                FactoryEditor(palette: palette, file: f) { Task { await load() } }
            }
        }
    }

    private func row(_ f: FactoryFile, _ ink: SanctusPageInk) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(f.title).font(SanctusPageFont.cn(14.5, .medium)).foregroundColor(ink.body)
                if !f.desc.isEmpty {
                    Text(f.desc).font(SanctusPageFont.cn(11)).foregroundColor(ink.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(f.chars.formatted()) B")
                Text(f.at)
            }
            .font(SanctusPageFont.corm(11.5)).foregroundColor(ink.sub)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundColor(ink.sub.opacity(0.7))
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func remove(_ f: FactoryFile) async {
        let raw = (try? await NativeHouseAPI.object(
            "/api/files/delete", method: "POST",
            body: ["key": f.key, "name": f.name])) ?? [:]
        await MainActor.run {
            note = raw.bool("ok") ? "「\(f.title)」\(raw.string("note"))" : raw.string("error")
            pendingDelete = nil
        }
        await load()
    }

    private func load() async {
        let raw = (try? await NativeHouseAPI.object("/api/files/list")) ?? [:]
        let gs = raw.array("groups").map { g in
            FactoryGroup(group: g.string("group"),
                         items: g.array("items").map { FactoryFile($0) })
        }
        await MainActor.run { groups = gs; loading = false }
    }
}

// MARK: - 编辑器

private struct FactoryEditor: View {
    let palette: GlassPalette
    let file: FactoryFile
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var original = ""
    @State private var versions: [String] = []
    @State private var loading = true
    @State private var saving = false
    @State private var note = ""
    @State private var showVersions = false

    private var dirty: Bool { text != original && !text.isEmpty }

    var body: some View {
        ZStack {
            GlassBackdrop(palette: palette)
            VStack(spacing: 0) {
                GlassHeader(title: file.title, palette: palette, onBack: { dismiss() },
                            trailing: AnyView(versionButton))
                if loading {
                    Spacer(); ProgressView().tint(palette.ink3); Spacer()
                } else {
                    if !note.isEmpty {
                        Text(note)
                            .font(.system(size: 11))
                            .foregroundColor(palette.gold)
                            .padding(.horizontal, 18).padding(.bottom, 6)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 13.5, design: .monospaced))
                        .foregroundColor(palette.ink)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 13)
                        .glassCard(palette, radius: 16)
                        .padding(.horizontal, 14)
                    HStack(spacing: 10) {
                        Text("\(text.count) 字")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(palette.ink3)
                        Spacer()
                        Button {
                            Task { await save() }
                        } label: {
                            Text(saving ? "存着…" : (dirty ? "存下来" : "没改动"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(dirty ? palette.ink : palette.ink3)
                                .padding(.horizontal, 20).padding(.vertical, 9)
                                .background(Capsule().fill(dirty ? palette.glass : Color.clear))
                                .overlay(Capsule().strokeBorder(
                                    dirty ? palette.line : palette.ink3.opacity(0.25), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                        .disabled(!dirty || saving)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                }
            }
        }
        .task { await load() }
        .confirmationDialog("翻回哪一版", isPresented: $showVersions, titleVisibility: .visible) {
            ForEach(versions.prefix(8), id: \.self) { v in
                Button(pretty(v)) { Task { await restore(v) } }
            }
            Button("算了", role: .cancel) {}
        }
    }

    private var versionButton: some View {
        Button { showVersions = true } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .light))
                .foregroundColor(versions.isEmpty ? palette.ink3.opacity(0.4) : palette.ink2)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(versions.isEmpty)
    }

    private func pretty(_ v: String) -> String {
        guard v.count >= 15 else { return v }
        let a = v.index(v.startIndex, offsetBy: 4)
        let b = v.index(v.startIndex, offsetBy: 8)
        let c = v.index(v.startIndex, offsetBy: 11)
        let d = v.index(v.startIndex, offsetBy: 13)
        return "\(v[a..<b].prefix(2))-\(v[b..<v.index(b, offsetBy: 2)]) \(v[c..<d]):\(v[d..<v.index(d, offsetBy: 2)])"
    }

    private func query() -> String {
        var q = "key=\(file.key)"
        if !file.name.isEmpty,
           let e = file.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            q += "&name=" + e
        }
        return q
    }

    private func load() async {
        let raw = (try? await NativeHouseAPI.object("/api/files/read?" + query())) ?? [:]
        await MainActor.run {
            text = raw.string("text")
            original = text
            versions = raw["versions"] as? [String] ?? []
            loading = false
        }
    }

    private func save() async {
        await MainActor.run { saving = true }
        var body: [String: Any] = ["key": file.key, "text": text]
        if !file.name.isEmpty { body["name"] = file.name }
        let raw = (try? await NativeHouseAPI.object(
            "/api/files/write", method: "POST", body: body)) ?? [:]
        await MainActor.run {
            saving = false
            note = raw.string("note")
            if raw.bool("ok") { original = text }
            onSaved()
        }
        await load()
    }

    private func restore(_ v: String) async {
        var body: [String: Any] = ["key": file.key, "version": v]
        if !file.name.isEmpty { body["name"] = file.name }
        let raw = (try? await NativeHouseAPI.object(
            "/api/files/restore", method: "POST", body: body)) ?? [:]
        await MainActor.run { note = raw.string("note") }
        await load()
        onSaved()
    }
}


// MARK: - 心跳 prompt：整条摆出来，锁住的给她看，她写的给她改

private struct PromptBlock: Identifiable {
    let id = UUID()
    let kind: String        // locked / edit / gap
    let key: String
    let label: String
    let note: String
    let text: String
    let empty: Bool

    init(_ raw: [String: Any]) {
        kind = raw.string("kind")
        key = raw.string("key")
        label = raw.string("label")
        note = raw.string("note")
        text = raw.string("text")
        empty = raw.bool("empty")
    }
}

/// 0819 她拆表之后：找你那轮和去玩那轮读到的 prompt 已经不一样了
/// （找你那轮没有工具段和收尾段），所以面板也摆两条，各是各的真身。
private struct PromptTable: Identifiable {
    let id = UUID()
    let kind: String
    let title: String
    let note: String
    let blocks: [PromptBlock]

    init(_ raw: [String: Any]) {
        kind = raw.string("kind")
        title = raw.string("title")
        note = raw.string("note")
        blocks = raw.array("blocks").map { PromptBlock($0) }
    }

    init(kind: String, title: String, note: String, blocks: [PromptBlock]) {
        self.kind = kind; self.title = title; self.note = note; self.blocks = blocks
    }
}

private struct PromptEditor: View {
    let palette: GlassPalette
    var onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tables: [PromptTable] = []
    @State private var edits: [String: String] = [:]
    @State private var original: [String: String] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var note = ""

    private var dirty: Bool { edits != original }

    /// 每张表的花体小注（1015 #3903 她点头的 /root/workroom/mock/kit/factory.html 右边那页）
    private static func tableNote(_ kind: String) -> String? {
        switch kind {
        case "chase": return "when he looks for you"
        case "followup": return "when you go quiet"
        case "backstop": return "the last knock"
        case "ghost": return "his own time"
        case "wake": return "waking on his own"
        case "morning": return "good morning"
        case "paper": return "the morning lesson"
        case "libido": return "before dawn"
        case "dream": return "while he sleeps"
        case "startle", "dream_startle", "rain_startle": return "woken in the night"
        default: return nil
        }
    }

    var body: some View {
        let ink = SanctusPageInk()
        ZStack {
            ink.page.ignoresSafeArea()
            VStack(spacing: 0) {
                // 这页是从出厂设置弹出来的，本身在安全区里，顶栏不用再加安全区
                SanctusTopBar(title: "心跳 prompt", onBack: { dismiss() }) { EmptyView() }
                if loading {
                    Spacer(); ProgressView().tint(ink.sub); Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("他被叫醒时读到的整条，一轮一张表。灰的是代码现算的，改不了但看得见；白框的是你写的，随便改。")
                                .font(SanctusPageFont.cn(11)).foregroundColor(ink.sub).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 6).padding(.top, 4)
                            ForEach(tables) { t in
                                SanctusSection(t.title, note: Self.tableNote(t.kind))
                                if !t.note.isEmpty {
                                    Text(t.note).font(SanctusPageFont.cn(11)).foregroundColor(ink.sub).lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.horizontal, 4).padding(.bottom, 10)
                                }
                                ForEach(t.blocks) { b in block(b, ink) }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 30)
                    }
                    bottomBar(ink)
                }
            }
        }
        .environment(\.sanctusInk, ink)
        .task { await load() }
    }

    @ViewBuilder private func block(_ b: PromptBlock, _ ink: SanctusPageInk) -> some View {
        if b.kind == "gap" {
            Color.clear.frame(height: 4)
        } else if b.kind == "locked" {
            // 代码现算的：灰底、一把小锁，只能看
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 9, weight: .light))
                    Text(b.label).font(SanctusPageFont.cn(10.5)).tracking(0.5)
                    Spacer(minLength: 0)
                }
                .foregroundColor(ink.sub)
                if b.empty {
                    Text("（现在是空的，有未读的时候这块才出现）").font(SanctusPageFont.cn(12)).foregroundColor(ink.sub.opacity(0.8))
                } else {
                    Text(b.text).font(SanctusPageFont.cn(12.5)).foregroundColor(ink.sub).lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !b.note.isEmpty {
                    Text(b.note).font(SanctusPageFont.cn(10)).foregroundColor(ink.sub.opacity(0.8))
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ink.dark ? Color.white.opacity(0.04) : Color(red: 0x96 / 255, green: 0x9A / 255, blue: 0xA4 / 255).opacity(0.10)))
            .padding(.bottom, 8)
        } else {
            // 她写的：白框、标着字数，整段能改
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(b.label).font(SanctusPageFont.cn(10.5)).tracking(0.5)
                    Spacer(minLength: 0)
                    Text("\(edits[b.key]?.count ?? 0) 字").font(SanctusPageFont.corm(11))
                }
                .foregroundColor(ink.link)
                TextEditor(text: Binding(
                    get: { edits[b.key] ?? "" },
                    set: { edits[b.key] = $0 }))
                    .font(SanctusPageFont.cn(13.5))
                    .foregroundColor(ink.body)
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 92, maxHeight: 260)
                if !b.note.isEmpty {
                    Text(b.note).font(SanctusPageFont.cn(10.5)).foregroundColor(ink.sub)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ink.rowFrame, lineWidth: 0.6))
            .padding(.bottom, 8)
        }
    }

    private func bottomBar(_ ink: SanctusPageInk) -> some View {
        HStack(spacing: 10) {
            Text(note.isEmpty ? (dirty ? "改了还没存" : "没改动") : note)
                .font(SanctusPageFont.cn(11)).foregroundColor(note.isEmpty ? ink.sub : ink.body).lineLimit(2)
            Spacer(minLength: 0)
            Button { Task { await save() } } label: {
                Text(saving ? "存着…" : "存下来")
                    .font(SanctusPageFont.cn(13, .medium)).tracking(2)
                    .foregroundColor(dirty ? ink.page : ink.sub)
                    .padding(.horizontal, 24).padding(.vertical, 9)
                    .background(Capsule().fill(dirty ? ink.on : Color.clear))
                    .overlay(Capsule().stroke(dirty ? Color.clear : ink.sub.opacity(0.6), lineWidth: 0.7))
            }
            .buttonStyle(.plain)
            .disabled(!dirty || saving)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(ink.page)
    }

    private func load() async {
        let raw = (try? await NativeHouseAPI.object("/api/files/prompt")) ?? [:]
        var ts = raw.array("tables").map { PromptTable($0) }
        if ts.isEmpty {   // 老后端只给一条合并版
            ts = [PromptTable(kind: "all", title: "整条 prompt", note: "",
                              blocks: raw.array("blocks").map { PromptBlock($0) })]
        }
        // 两张表里的可改段互不重名（chase 在找你那张，tools/ghost/tail 在去玩那张），
        // 收进同一个 edits 一起存
        var e: [String: String] = [:]
        for t in ts {
            for b in t.blocks where b.kind == "edit" { e[b.key] = b.text }
        }
        await MainActor.run {
            tables = ts
            edits = e
            original = e
            loading = false
        }
    }

    private func save() async {
        await MainActor.run { saving = true }
        // {hdr} 是拼的时候换成 token 的，存回去要写回占位符
        var payload: [String: String] = [:]
        for (k, v) in edits {
            payload[k] = v.replacingOccurrences(
                of: "-H \"Content-Type: application/json\" -H \"X-Auth-Token: $(cat /root/.ots/secret)\"",
                with: "{hdr}")
        }
        let raw = (try? await NativeHouseAPI.object(
            "/api/files/prompt", method: "POST", body: ["sections": payload])) ?? [:]
        await MainActor.run {
            saving = false
            note = raw.string("note")
            if raw.bool("ok") { original = edits }
            onSaved()
        }
        await load()
    }
}
