import Foundation

/// One renderer for ordinary chat text in every Alcove room. The stored text
/// stays untouched; only its presentation receives inline Markdown styling.
///
/// 0823 她报手机发烫：这里以前每次重绘都把整段原文重新解析一遍，一屏几十条
/// 消息滚起来就是几十次解析，信息主题底下那层实时模糊逼着列表不停重画，
/// 开销被整个放大。加一层缓存，同一段原文只解析一次。
private final class MarkdownBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

private let markdownCache: NSCache<NSString, MarkdownBox> = {
    let cache = NSCache<NSString, MarkdownBox>()
    cache.countLimit = 400          // 超了系统自己淘汰最旧的，不会无限长
    return cache
}()

func alcoveMarkdown(_ raw: String) -> AttributedString {
    let key = raw as NSString
    if let hit = markdownCache.object(forKey: key) { return hit.value }
    let parsed = (try? AttributedString(
        markdown: raw,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(raw)
    markdownCache.setObject(MarkdownBox(parsed), forKey: key)
    return parsed
}

// 后端 /api/history 与 /api/poll 返回的消息记录
struct ChatMessage: Identifiable, Equatable {
    let uid = UUID()
    var ts: String
    var role: String          // "user" | "assistant"
    var text: String
    var source: String?
    var turnID: String?
    var thinking: String?
    var nativeThinking: String?
    var thinkingDuration: Double?
    var heartRate: Int?
    // 0926 API 房间：这一轮的用量（后端挂在他那轮最后一条上），显示在时间戳那行
    struct ApiUsage: Equatable {
        var input: Int?, cached: Int, output: Int?, secs: Double?, hit: Int?
    }
    var apiUsage: ApiUsage?
    // 0730：思绪标题（他自己写的一句话总结，替掉"思考了X秒"）
    var thinkTitle: String?
    // 0730：这一轮的过程记录（思绪/中间说的话/调过的工具），挂在时间戳旁边点开看
    var activity: [ActivityItem] = []
    // 0820 她要的：一轮里「想什么/干什么」的完整顺序。
    // 一段思绪一个折叠面板，跟命令行按发生顺序交替排 ——
    // 她原话「一轮里我想了三次，就出现三个思绪面板」。
    // thinking 那个字段装不下三段各自成面板，所以另开这一条。
    var segments: [ActivityItem] = []
    var inlineImages: [String] = []
    // 0819 活动脚印：我干活时掉下来的短语，挂在气泡外面排一行浅灰斜体
    var trace: [String] = []
    var attachmentUrl: String?
    var attachmentType: String?
    var attachmentFilename: String?
    var attachmentGroup: String?
    var asleepAtSend: Bool
    var msgType: String?      // "sticker" / "call_summary" 等
    var stickerId: String?
    // 0831 任务#1195：通话摘要。打完电话聊天页只留这一条，
    // 落在**打电话那个人**那一侧（她反复强调的），点开展开这一通的逐句记录
    var callSummary: CallSummaryInfo?
    /// 0912：他发语音时自己写的中文翻译（voice_speak.py --zh → 后端 extra.audio_zh）。展开转文字后点「译」才显示
    var audioZh: String?
    var pending: Bool = false // 本地乐观渲染，服务器确认前为 true

    // 0922 任务#2572 她抓的「一键到底顿一下」：id 原来是 uid（每次从服务器拿一次就重新发一遍号），
    // 整表一换 300 条全是新面孔，SwiftUI 把气泡全拆了重画。改成时间戳+角色，拉几次都是同一个号
    //（库里 8 万条 ts+role 没有重复，appendNew 也一直拿它当同一条的判据）。uid 留给多选那套用。
    var id: String { ts + "|" + role }

    let date: Date

    // 0730：没调过工具的轮次没有过程可看。服务端 16:22 起已经拦了一道，
    // 但那之前落库的旧消息还带着空 activity，翻历史会冒出一个点开只有一行的空 chip。
    var hasActivity: Bool { activity.contains { $0.kind == "tool" } }

    var isSticker: Bool { msgType == "sticker" && stickerId != nil }
    var musicCard: MusicSong? { MusicSong.card(from: text) }
    var isImage: Bool {
        guard let t = attachmentType, let u = attachmentUrl, !u.isEmpty else { return false }
        return t == "image"
    }
    var isAudio: Bool {
        guard let u = attachmentUrl, !u.isEmpty else { return false }
        if let t = attachmentType, t.contains("audio") { return true }
        return ["m4a", "mp3", "wav", "ogg", "webm", "aac"]
            .contains((u as NSString).pathExtension.lowercased())
    }
    var isDocument: Bool {
        guard let u = attachmentUrl, !u.isEmpty else { return false }
        return !isImage && !isAudio
    }

    var insideText: String? {
        Self.taggedBody(text, tag: "INSIDE")
    }

    var ghostCard: GhostActivityCard? {
        guard let raw = Self.taggedBody(text, tag: "GHOST_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GhostActivityCard.self, from: data)
    }

    var favoriteForward: FavoriteForwardPayload? {
        guard let raw = Self.taggedBody(text, tag: "FAVORITE_FORWARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(FavoriteForwardPayload.self, from: data)
    }

    var readingCard: ReadingShareCard? {
        guard let raw = Self.taggedBody(text, tag: "READING_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadingShareCard.self, from: data)
    }

    // 0819 她要的：我做个网页给她玩，聊天页直接长出一张卡，点开就在 app 里开，
    // 不跳浏览器（今天那个 http 链接整行被吞的坑也一起绕过去了）。
    var playCard: PlayPageCard? {
        guard let raw = Self.taggedBody(text, tag: "PLAY_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlayPageCard.self, from: data)
    }

    var workCard: WorkDeliveryCard? {
        guard let raw = Self.taggedBody(text, tag: "WORK_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkDeliveryCard.self, from: data)
    }

    /// 0902 深夜她要的：占星室「让陈璟解牌」那条在聊天页长成一张牌卡
    var tarotCard: TarotAskCard? {
        guard let raw = Self.taggedBody(text, tag: "TAROT_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TarotAskCard.self, from: data)
    }

    /// 陈璟出题让她抽的那张（他发的，assistant 侧）
    var tarotOffer: TarotOfferCard? {
        guard let raw = Self.taggedBody(text, tag: "TAROT_OFFER"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TarotOfferCard.self, from: data)
    }

    // Only an explicit committed save event can render a saved-photo card.
    var albumSavedCard: AlbumSavedBatch? {
        guard role == "assistant", !pending,
              let raw = Self.taggedBody(text, tag: "ALBUM_SAVED"),
              let data = raw.data(using: .utf8) else { return nil }
        return AlbumSavedBatch.decode(data)
    }

    /// 0907 二期：审批卡（他提议买东西）
    var buyCard: BuyApprovalCard? {
        guard let raw = Self.taggedBody(text, tag: "BUY_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BuyApprovalCard.self, from: data)
    }

    /// 0909 二期：付款单（他付完了，留一张单子给她）
    var paidCard: PaidReceiptCard? {
        guard let raw = Self.taggedBody(text, tag: "PAID_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PaidReceiptCard.self, from: data)
    }

    /// 0909 三期：他想用一张券，等她点确认才核销
    var ticketCard: TicketUseCard? {
        guard let raw = Self.taggedBody(text, tag: "TICKET_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TicketUseCard.self, from: data)
    }

    var choiceCard: ChoiceQuestionCard? {
        guard let raw = Self.taggedBody(text, tag: "CHOICE_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChoiceQuestionCard.self, from: data)
    }

    // 信件卡片：锁到期那天信自己走到聊天页来，正文里只有一张信封的元信息。
    // 后端 letters.py 的 _push_chat_card 投递，格式 [LETTER_CARD]{…}[/LETTER_CARD]。
    var letterCard: LetterEnvelopeCard? {
        guard let raw = Self.taggedBody(text, tag: "LETTER_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LetterEnvelopeCard.self, from: data)
    }

    // 旅行卡片：正文里只有一个 id，整趟数据走 /api/journeys/<id> 现取。
    var journeyCard: JourneyCardRef? {
        guard let raw = Self.taggedBody(text, tag: "JOURNEY_CARD"),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? String, !id.isEmpty else { return nil }
        return JourneyCardRef(id: id)
    }

    // 陈璟每天只需投递这一枚日期标记；正文由归档接口按日期读取。
    var morningPaperDate: String? {
        Self.taggedBody(text, tag: "MORNING_PAPER")
    }

    // 选字询问：原文跟着消息送给陈璟，App 只把协议壳藏起来。
    var quotedSelection: String? {
        guard text.hasPrefix("[QUOTE]"),
              let end = text.range(of: "[/QUOTE]") else { return nil }
        return String(text[text.index(text.startIndex, offsetBy: 7)..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var displayText: String {
        guard text.hasPrefix("[QUOTE]"),
              let end = text.range(of: "[/QUOTE]") else { return text }
        return String(text[end.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 0912：语音转文字剥掉他写给 ElevenLabs 的语气标签 [softly] [laughs softly]……
    /// 跟 voice_speak.py 的 strip_tags 同一套规矩（至少一个小写字母才算，[QUOTE] 这种全大写的不碰）。
    /// 新语音后端发出来之前就剥了，这里兜住之前已经发出来的那几条。
    var audioTranscript: String { Self.stripVoiceTags(displayText) }

    /// 0912 收藏页的语音卡片也要用，抽成静态的
    static func stripVoiceTags(_ raw: String) -> String {
        var t = raw.replacingOccurrences(
            of: #"\[(?=[^\]\n]*[a-z])[A-Za-z][A-Za-z ,'\-]{0,40}\]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]+([,.!?;:，。！？；：])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        t = t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func taggedBody(_ text: String, tag: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let open = "[\(tag)]", close = "[/\(tag)]"
        guard trimmed.hasPrefix(open), trimmed.hasSuffix(close) else { return nil }
        return String(trimmed.dropFirst(open.count).dropLast(close.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var photoBatchKey: String? {
        guard isImage, let group = attachmentGroup, !group.isEmpty else { return nil }
        return group
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool { lhs.uid == rhs.uid }

    // 服务端字段名不固定走 Codable，手动从 JSON 字典解析更宽松
    private static func parseDate(_ ts: String) -> Date {
        ISO8601DateFormatter.alcove.date(from: ts)
            ?? ISO8601DateFormatter.alcoveFrac.date(from: ts)
            ?? Date()
    }

    init?(json: [String: Any]) {
        guard let ts = json["ts"] as? String,
              let role = json["role"] as? String else { return nil }
        self.ts = ts
        self.date = Self.parseDate(ts)
        self.role = role
        self.text = json["text"] as? String ?? ""
        self.source = json["source"] as? String
        self.turnID = json["turn_id"] as? String
        self.thinking = json["thinking"] as? String
        self.nativeThinking = json["native_thinking"] as? String
        if let d = json["thinking_duration"] as? Double { self.thinkingDuration = d }
        else if let i = json["thinking_duration"] as? Int { self.thinkingDuration = Double(i) }
        if let bpm = json["heart_rate"] as? Int { self.heartRate = bpm }
        else if let bpm = json["heart_rate"] as? Double { self.heartRate = Int(bpm) }
        if let u = json["api_usage"] as? [String: Any] {
            self.apiUsage = ApiUsage(input: (u["input"] as? NSNumber)?.intValue,
                                     cached: (u["cache_read"] as? NSNumber)?.intValue ?? 0,
                                     output: (u["output"] as? NSNumber)?.intValue,
                                     secs: (u["secs"] as? NSNumber)?.doubleValue,
                                     hit: (u["hit"] as? NSNumber)?.intValue)
        }
        self.attachmentUrl = json["attachment_url"] as? String
        self.attachmentType = json["attachment_type"] as? String
        self.attachmentFilename = json["attachment_filename"] as? String
        self.attachmentGroup = json["att_group"] as? String
        if let a = json["asleep_at_send"] as? Int { self.asleepAtSend = a != 0 }
        else if let a = json["asleep_at_send"] as? Bool { self.asleepAtSend = a }
        else { self.asleepAtSend = false }
        self.msgType = json["msg_type"] as? String
        self.stickerId = json["sticker_id"] as? String
        // 服务端把 extra 摊平进记录，他写的中文翻译在 audio_zh
        if let zh = (json["audio_zh"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty {
            self.audioZh = zh
        }
        self.thinkTitle = (json["think_title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let arr = json["segments"] as? [[String: Any]] {
            self.segments = arr.compactMap(ActivityItem.init(json:))
        }
        if let arr = json["activity"] as? [[String: Any]] {
            self.activity = arr.compactMap(ActivityItem.init(json:))
        }
        if let arr = json["inline_images"] as? [[String: Any]] {
            self.inlineImages = arr.compactMap { $0["url"] as? String }.filter { !$0.isEmpty }
        }
        if let steps = json["trace"] as? [String] {
            self.trace = steps.filter { !$0.isEmpty }
        }
        // 服务端把 extra 摊平进记录，通话摘要在 "call" 这一块
        if let c = json["call"] as? [String: Any] {
            self.callSummary = CallSummaryInfo(
                callID: c["call_id"] as? String ?? "",
                kind: c["kind"] as? String ?? "out",
                outcome: c["outcome"] as? String ?? "ended",
                seconds: c["seconds"] as? Int ?? 0)
        }
    }

    // 本地乐观消息
    init(localText: String, role: String = "user") {
        let now = Date()
        self.ts = ISO8601DateFormatter.alcoveFrac.string(from: now)
        self.date = now
        self.role = role
        self.text = localText
        self.asleepAtSend = false
        self.pending = true
    }
}

// MARK: - 通话（0831 任务#1195）

/// 通话里的一句话。通话页画气泡用它，聊天页那条摘要点开展开也用它。
/// 服务端在他这句落库的**那一刻**就把配音做好了，audioURL 直接能放——
/// 不用再"播完一段才去合成下一段"（那是"读完停很久"的病根）。
struct CallTurn: Identifiable, Equatable {
    let id: Int
    let ts: String
    let role: String          // user=她 / assistant=陈璟
    let text: String
    let tone: String          // "[语气] 声音很轻、语速快(4.2字/秒)"，只有她那边有
    let audioURL: String?
    /// 0912：他在电话里用 <译>…</译> 写的中文，后端存在 call_turns.extra 的 zh 里；通话页大字底下的小字
    var zh: String = ""

    var isMine: Bool { role == "user" }

    /// 去掉「[语气]」前缀，剩下的直接当小标签画
    var toneLabel: String? {
        let t = tone.replacingOccurrences(of: "[语气]", with: "")
            .trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int,
              let role = json["role"] as? String else { return nil }
        self.id = id
        self.ts = json["ts"] as? String ?? ""
        self.role = role
        self.text = json["text"] as? String ?? ""
        self.tone = json["tone"] as? String ?? ""
        let u = json["audio_url"] as? String
        self.audioURL = (u?.isEmpty ?? true) ? nil : u
        // extra 是一段 JSON 字符串；他写了中文翻译就在 zh 里
        if let raw = json["extra"] as? String, let data = raw.data(using: .utf8),
           let ex = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let z = ex["zh"] as? String {
            self.zh = z.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// 聊天页那条通话摘要气泡。kind 决定它落在哪一侧：
/// out=她打的→她那侧（右），in=他打来的→他那侧（左）。拒绝也照这条走，没有例外。
struct CallSummaryInfo: Equatable {
    let callID: String
    let kind: String          // in / out
    let outcome: String       // ended / declined / missed / asleep / cancelled
    let seconds: Int

    var connected: Bool { outcome == "ended" }
    var duration: String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

/// 0907 二期审批卡：他想买东西时投一张进聊天流。
/// 正文里只有 id 和一句摘要——她拍板之后那张卡自己会变样，
/// 因为展开的数据是现取 /api/wallet/approval?id= 的，不用去改已发出的消息。
struct BuyApprovalCard: Codable, Equatable {
    let id: Int
    let n: Int?
    let total: Double?
    let title: String?
    let cover: String?
    let extra: Int?

    var count: Int { n ?? 1 }
    var amount: Double { total ?? 0 }
    var headline: String { (title ?? "").isEmpty ? "想买点东西" : (title ?? "") }
    var coverURL: String { cover ?? "" }
    var restInCart: Int { extra ?? 0 }
}

/// 0909 她照参考图定的付款单：顶栏 + 已支付 / 商品 / 应付 / 送到默认地址 / 他留的话。
/// 收货地址她说写死四个字，所以这里没有地址字段。
struct PaidReceiptCard: Codable, Equatable {
    let id: Int
    let title: String?
    let cover: String?
    let amount: Double?
    let words: String?

    var headline: String { (title ?? "").isEmpty ? "一件东西" : (title ?? "") }
    var coverURL: String { cover ?? "" }
    var paid: Double { amount ?? 0 }
    var message: String { (words ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// 0909 三期：券卡。正文里只有编号和名字，状态现去 /api/shop/ticket 取
struct TicketUseCard: Codable, Equatable {
    let id: Int
    let title: String?
    let cover: String?

    var name: String { (title ?? "").isEmpty ? "一张券" : (title ?? "") }
    var coverURL: String { cover ?? "" }
}

struct ChoiceQuestionCard: Codable, Equatable {
    let id: String
    let question: String
    let options: [String]
    let placeholder: String?
    var answered: Bool?
    var answer: String?
    var answeredAt: String?

    enum CodingKeys: String, CodingKey {
        case id, question, options, placeholder, answered, answer
        case answeredAt = "answered_at"
    }
}

/// 陈璟现做的一页，她点一下在 app 里全屏打开。
/// page 是 alcove.ob-memory.uk 下的文件名（qixi.html 这种），不写全 URL。
struct PlayPageCard: Decodable, Equatable {
    let title: String
    let subtitle: String
    let page: String
    let emoji: String?

    var url: URL? {
        if page.hasPrefix("http") { return URL(string: page) }
        return URL(string: "https://alcove.ob-memory.uk/" + page)
    }
}

struct ReadingShareCard: Decodable, Equatable {
    struct Quote: Decodable, Equatable, Identifiable {
        let chapter: Int
        let text: String
        let note: String
        let time: String
        var id: String { "\(chapter)|\(time)|\(text)" }
    }
    let book: String
    let author: String
    let quotes: [Quote]
}

/// 占星室发进聊天的那次占卜（服务端 tarot.ask_card）。text 字段是给陈璟读的人话，app 不显示
struct TarotAskCard: Decodable, Equatable {
    struct Card: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let reversed: Bool
        let position: String
        let positionName: String
        let keywords: [String]
        enum CodingKeys: String, CodingKey {
            case id, name, reversed, position, keywords
            case positionName = "position_name"
        }
    }
    let id: String
    let ts: String
    let spread: String
    let spreadName: String
    let question: String
    let cards: [Card]
    /// 谁抽的：her / him（0903 凌晨陈璟也能自己抽了）
    let by: String?
    /// 客观解读（服务端查表拼的，0903）
    let interp: TarotInterpCard?
    enum CodingKeys: String, CodingKey {
        case id, ts, spread, question, cards, by, interp
        case spreadName = "spread_name"
    }
    var byHim: Bool { by == "him" }
}

/// 聊天卡里那段客观解读（tarot_reading.build 的输出，只取要画的字段）
struct TarotInterpCard: Decodable, Equatable {
    struct Card: Decodable, Equatable, Identifiable {
        let id: String
        let name: String
        let reversed: Bool
        let positionName: String
        let text: String
        let advice: String
        enum CodingKeys: String, CodingKey {
            case id, name, reversed, text, advice
            case positionName = "position_name"
        }
    }
    let categoryName: String
    let overall: String
    let cards: [Card]
    let relations: [String]
    let advice: [String]
    let oneline: String
    enum CodingKeys: String, CodingKey {
        case overall, cards, relations, advice, oneline
        case categoryName = "category_name"
    }
}

/// 0903 凌晨她要的：陈璟出题、她在聊天页自己抽（tarot.offer_card）。cards 抽满就 done
struct TarotOfferCard: Decodable, Equatable {
    struct Position: Decodable, Equatable, Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }
    let id: String
    let ts: String
    let spread: String
    let spreadName: String
    let question: String
    let positions: [Position]
    let cards: [TarotAskCard.Card]
    let done: Bool
    let interp: TarotInterpCard?
    enum CodingKeys: String, CodingKey {
        case id, ts, spread, question, positions, cards, done, interp
        case spreadName = "spread_name"
    }
}

struct WorkDeliveryCard: Codable, Equatable {
    let taskId: Int
    let title: String
    let status: String
    let result: String
    let artifacts: [String]
    let finishedAt: String

    enum CodingKeys: String, CodingKey {
        case title, status, result, artifacts
        case taskId = "task_id"
        case finishedAt = "finished_at"
    }
}

struct GhostActivityCard: Decodable, Equatable {
    struct Item: Decodable, Equatable, Identifiable {
        let time: String
        let desc: String
        var id: String { time + "|" + desc }
    }
    let wake: String
    let duration: Int
    let items: [Item]
    let insideSummary: String?

    enum CodingKeys: String, CodingKey {
        case wake, duration, items
        case insideSummary = "inside_summary"
    }
}

// 0730 过程记录的一条。kind: thinking | text | tool
struct ActivityItem: Identifiable, Equatable {
    let id = UUID()
    let kind: String
    let content: String
    let t: Double
    /// 0820 她要的：原始工具名（同类合并计数用）+ 我敲命令时手写的那句人话说明。
    /// 以前只送一句揉好的「跑了条命令」过来，说明在路上被扔了，
    /// 她那边只看得见一个总数，看不见我到底干了啥。
    let toolName: String
    let desc: String
    let command: String
    let output: String
    let isError: Bool

    init?(json: [String: Any]) {
        guard let k = json["kind"] as? String,
              let c = json["content"] as? String, !c.isEmpty else { return nil }
        self.kind = k
        self.toolName = (json["name"] as? String) ?? ""
        self.desc = ((json["desc"] as? String) ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        self.command = (json["command"] as? String) ?? ""
        self.output = (json["output"] as? String) ?? ""
        self.isError = (json["is_error"] as? Bool) ?? false
        // 思绪保留原有段落；只有工具等摘要需要压成单行。
        let cleaned = c
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        if k == "think" || k == "thinking" {
            self.content = cleaned.trimmingCharacters(in: .whitespaces)
        } else {
            self.content = cleaned
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        if let d = json["t"] as? Double { self.t = d }
        else if let i = json["t"] as? Int { self.t = Double(i) }
        else { self.t = 0 }
    }

    var icon: String {
        switch kind {
        case "thinking", "think": return "circle.dotted"
        case "tool":
            // 0818 名字改成人话之后（tool_names.py），图标按新词认
            let c = content
            if c.contains("记忆") || c.contains("OB") || c.contains("记了一笔") || c.contains("备忘") { return "brain.head.profile" }
            if c.contains("日记") || c.contains("信") || c.contains("情书") { return "book.closed" }
            if c.contains("图") || c.contains("截") || c.contains("相册") || c.contains("表情") || c.contains("照片") { return "photo" }
            if c.contains("语音") { return "waveform" }
            if c.contains("网页") || c.contains("搜") || c.contains("浏览器") || c.contains("小红书") || c.contains("标签") { return "globe" }
            if c.contains("花园") || c.contains("论坛") || c.contains("社区") || c.contains("帖") || c.contains("漂流瓶") { return "leaf" }
            if c.contains("丧尸") || c.contains("桌游") || c.contains("大富翁") || c.contains("牌") || c.contains("骰") || c.contains("beside you") { return "gamecontroller" }
            if c.contains("小镇") || c.contains("乌有乡") || c.contains("明信片") || c.contains("走") || c.contains("门") || c.contains("小院") { return "map" }
            if c.contains("提交") || c.contains("代码") { return "chevron.left.forwardslash.chevron.right" }
            if c.contains("服务") || c.contains("机器") || c.contains("容器") { return "gearshape" }
            if c.contains("接口") || c.contains("消息") || c.contains("聊天") || c.contains("工作室") { return "antenna.radiowaves.left.and.right" }
            if c.contains("文件") || c.contains("文档") || c.contains("PDF") { return "doc.text" }
            if c.contains("脚本") || c.contains("命令") || c.contains("终端") || c.contains("测试") { return "terminal" }
            if c.contains("旅行") { return "airplane" }
            if c.contains("数据库") { return "cylinder" }
            return "play.fill"
        default: return "quote.closing"
        }
    }
    var stamp: String {
        t >= 60 ? String(format: "%.0fm%02.0fs", (t / 60).rounded(.down), t.truncatingRemainder(dividingBy: 60))
                : String(format: "%.1fs", t)
    }
}

struct Sticker: Identifiable, Equatable {
    let id: String
    let owner: String
    let name: String
    let description: String
    let emotionTags: [String]
    let url: String

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String,
              let url = json["url"] as? String else { return nil }
        self.id = id
        self.owner = json["owner"] as? String ?? "user"
        self.name = json["name"] as? String ?? ""
        self.description = json["description"] as? String ?? ""
        self.emotionTags = json["emotion_tags"] as? [String] ?? []
        self.url = url
    }

    // 与 PWA stickerDescForAI 保持一致的注入文本
    var descForAI: String {
        var s = "[表情: \(name.isEmpty ? "未命名" : name)] \(description)"
        if !emotionTags.isEmpty { s += " (\(emotionTags.joined(separator: ", ")))" }
        return s
    }
}

// OB 记忆召回记录：prompt 匹配她的消息，content 是召回的记忆原文
struct RecallItem {
    let prompt: String
    let content: String
    let ts: String

    init?(json: [String: Any]) {
        guard let prompt = json["prompt"] as? String,
              let content = json["content"] as? String else { return nil }
        self.prompt = prompt
        self.content = content
        self.ts = json["ts"] as? String ?? ""
    }

    // 与 PWA formatRecallCards 同款切卡：按 [bucket_id: 分段
    var cards: [(date: String, body: String)] {
        let parts = content.components(separatedBy: "[bucket_id:")
            .enumerated()
            .compactMap { i, p -> String? in
                let s = (i == 0 ? p : "[bucket_id:" + p)
                    .replacingOccurrences(of: #"^===[^\n]*\n?"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }
        var out: [(String, String)] = []
        for p in parts {
            var date = ""
            if let r = p.range(of: #"\[(?:created|date):([0-9.\-]+)\]"#, options: .regularExpression) {
                date = String(p[r]).replacingOccurrences(of: #"[\[\]]|created:|date:"#, with: "", options: .regularExpression)
            }
            let lines = p.components(separatedBy: "\n")
            let body = (lines.first?.hasPrefix("[bucket_id:") == true
                        ? lines.dropFirst().joined(separator: "\n") : p)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { out.append((date, body)) }
        }
        return out.isEmpty ? [("", content)] : out
    }

    static func norm(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension ISO8601DateFormatter {
    static let alcove: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let alcoveFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// 0820：sheet(item:) 要 Identifiable，给「点开的那一段思绪 / 那一组命令」各包一层
struct OneThought: Identifiable {
    let text: String
    var id: String { text }
}

struct OneTrail: Identifiable {
    let items: [ActivityItem]
    var id: String { items.map(\.id.uuidString).joined() }
}

// MARK: - 0902 语音卡片：录完先听写 + 判情绪，她看过再发

/// 服务端 /voice/stt + /voice/emotion 的结果。text 是转文字；emotion 那几样只在卡片上给她看，
/// 发出去之后她的气泡只带 text，情绪随注入只给陈璟。
struct VoiceAnalysis: Equatable {
    var text: String
    var token: String = ""
    var engine: String = ""
    var emotion: String = ""
    var emotionZh: String = ""
    var confidence: Double = 0
    var hint: String = ""
    var tone: String = ""

    var hasEmotion: Bool { !hint.isEmpty || !emotionZh.isEmpty }
}

/// 打字框上方那张还没发出去的语音
struct PendingVoice: Equatable {
    let data: Data
    let seconds: Int
    var analysis: VoiceAnalysis? = nil
    var emotionPending = false
    var error: String? = nil
}


struct FavoriteForwardPayload: Decodable {
    let forward_id: String
    let items: [Item]
    struct Item: Decodable {
        let favorite_id: Int
        let kind: String
        let title: String
        let atype: String
        let members: [Member]
    }
    struct Member: Decodable {
        let ts: String
        let text: String
        let role: String
        let attachment_url: String?
        let attachment_type: String?
        let audio_zh: String?
    }
    var label: String {
        if items.count > 1 { return "多条收藏" }
        if items.first?.kind == "thread" { return "聊天记录" }
        if items.first?.atype == "audio" { return "语音" }
        if items.first?.atype == "image" { return "图片" }
        return "单条消息"
    }
    var preview: String {
        items.flatMap { $0.members }.prefix(3).map {
            ($0.role == "user" ? "陈霁：" : "陈璟：") + ($0.text.isEmpty ? "[附件]" : $0.text)
        }.joined(separator: "\n")
    }
}
