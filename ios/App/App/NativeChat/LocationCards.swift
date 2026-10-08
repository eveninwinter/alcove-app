import SwiftUI
import MapKit
import CoreLocation

// MARK: - 1008 位置卡（她要的「iMessage 那样的发送位置」，效果图 /root/workroom/mock/location/mock.jpg，她说照 iMessage 原样、圆角卡片）
//
// 聊天里一条 [LOCATION_CARD]{json}[/LOCATION_CARD]（后端 alcove-backend/location_card.py）：
//   kind = place 一个地点（他用 place.py 发，或者她搜了发）/ current 她此刻在哪 / live 实时共享（带 share_id）
//   lat/lng 是 WGS-84，苹果地图直接用；text 是给他读的一句人话。
// 实时共享一直开着，直到她点「结束共享」；位置就是她手机平时上报的那份（SensorReporter），共享期间后台一分钟一报。

struct LocationChatCard: Codable, Equatable {
    let kind: String
    let name: String
    let address: String?
    let lat: Double
    let lng: Double
    let shareID: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case kind, name, address, lat, lng, text
        case shareID = "share_id"
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }

    /// 她这边发出去的那一整条（以她的身份走 /chat/send，他读 text）
    static func message(kind: String, name: String, address: String, coordinate c: CLLocationCoordinate2D,
                        shareID: String? = nil) -> String {
        let human: String
        switch kind {
        case "live": human = "[实时位置] 陈霁开始共享实时位置（一直共享到她自己点结束）。现在在：\(address.isEmpty ? name : address)"
        case "current": human = "[位置] 陈霁发来她现在的位置：\(address.isEmpty ? name : address)"
        default: human = "[位置] 陈霁发来一个地点：\(name)" + (address.isEmpty ? "" : "（\(address)）")
        }
        let card = LocationChatCard(kind: kind, name: name, address: address, lat: c.latitude, lng: c.longitude,
                                    shareID: shareID, text: human)
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        let json = (try? enc.encode(card)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "[LOCATION_CARD]" + json + "[/LOCATION_CARD]"
    }
}

extension ChatMessage {
    var locationCard: LocationChatCard? {
        guard let raw = Self.taggedBody(text, tag: "LOCATION_CARD"),
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LocationChatCard.self, from: data)
    }
}

// MARK: 地图截图（聊天列表里用截图不用活地图，滑起来不卡）

@MainActor
final class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private var images: [String: UIImage] = [:]

    func image(center: CLLocationCoordinate2D, size: CGSize, meters: Double, dark: Bool) async -> UIImage? {
        let key = String(format: "%.5f,%.5f,%.0f,%.0f,%.0f,%d", center.latitude, center.longitude, size.width, size.height, meters, dark ? 1 : 0)
        if let hit = images[key] { return hit }
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters)
        opts.size = size
        opts.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }
        images[key] = snap.image
        return snap.image
    }
}

// MARK: 实时共享的状态（卡片轮询 /api/places/share）

struct LiveShareState: Equatable {
    var active: Bool
    var lat: Double?
    var lng: Double?
    var address: String
    var ts: String

    init?(json: [String: Any]) {
        guard let share = json["share"] as? [String: Any] else { return nil }
        active = share["active"] as? Bool ?? false
        lat = share["lat"] as? Double
        lng = share["lng"] as? Double
        address = share["address"] as? String ?? ""
        ts = share["ts"] as? String ?? ""
    }
}

enum PlacesAPI {
    static func share(_ id: String) async -> LiveShareState? {
        guard let d = try? await NativeHouseAPI.object("/api/places/share?id=\(id)") else { return nil }
        return LiveShareState(json: d)
    }

    static func current() async -> (id: String, state: LiveShareState)? {
        guard let d = try? await NativeHouseAPI.object("/api/places/share"),
              let share = d["share"] as? [String: Any], let id = share["share_id"] as? String,
              let st = LiveShareState(json: d), st.active else { return nil }
        return (id, st)
    }

    static func start() async -> String? {
        guard let d = try? await NativeHouseAPI.object("/api/places/share/start", method: "POST", body: [:]) else { return nil }
        return d["share_id"] as? String
    }

    static func stop(_ id: String) async {
        _ = try? await NativeHouseAPI.object("/api/places/share/stop", method: "POST", body: ["share_id": id])
        if UserDefaults.standard.string(forKey: "placesLiveShareID") == id {
            UserDefaults.standard.removeObject(forKey: "placesLiveShareID")
        }
        NotificationCenter.default.post(name: .placesShareChanged, object: nil)
    }
}

extension Notification.Name {
    static let placesShareChanged = Notification.Name("placesShareChanged")
}

// MARK: - 聊天里那张卡

struct LocationMessageCard: View {
    let card: LocationChatCard
    let isUser: Bool
    // 深浅只认全屋那对白天 / 黑夜按钮（她定的死规矩），不看手机系统
    @AppStorage(AlcoveAppearance.key) private var houseAppearance = "dark"
    @AppStorage("userAvatarDataURL") private var userAvatar = ""
    @State private var snapshot: UIImage?
    @State private var live: LiveShareState?
    @State private var stopping = false

    private let width: CGFloat = 252
    private let mapHeight: CGFloat = 146
    private var dark: Bool { _ = houseAppearance; return AlcoveAppearance.isDark }
    private var ink: Color { dark ? .white : .black }
    private var dim: Color { dark ? Color(white: 0.62) : Color(red: 0.43, green: 0.43, blue: 0.45) }
    private var isLive: Bool { card.kind == "live" }
    private var liveActive: Bool { isLive && (live?.active ?? true) }

    private var center: CLLocationCoordinate2D {
        if let l = live, let lat = l.lat, let lng = l.lng { return .init(latitude: lat, longitude: lng) }
        return card.coordinate
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().aspectRatio(contentMode: .fill)
                } else {
                    (dark ? Color(white: 0.18) : Color(white: 0.9))
                }
                if isLive { liveMarker } else { pinMarker }
            }
            .frame(width: width, height: mapHeight)
            .clipped()
            info
        }
        .frame(width: width)
        .background(dark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color(red: 0.95, green: 0.95, blue: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { openInMaps() }
        .task(id: "\(center.latitude),\(center.longitude),\(dark)") {
            snapshot = await MapSnapshotCache.shared.image(center: center, size: CGSize(width: width, height: mapHeight),
                                                           meters: isLive ? 900 : 600, dark: dark)
        }
        .task(id: card.shareID ?? "") {
            guard isLive, let id = card.shareID, !id.isEmpty else { return }
            // 共享开着就半分钟问一次她在哪；结束了问一次拿到钉住的最后位置就停
            while !Task.isCancelled {
                if let s = await PlacesAPI.share(id) { live = s }
                if live?.active == false { break }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .placesShareChanged)) { _ in
            guard isLive, let id = card.shareID else { return }
            Task { if let s = await PlacesAPI.share(id) { live = s } }
        }
    }

    // 苹果地图那种红色大头针：针尖扎在正中间
    private var pinMarker: some View {
        VStack(spacing: -2) {
            Circle().fill(Color(red: 1, green: 0.23, blue: 0.19))
                .frame(width: 26, height: 26)
                .overlay(Circle().fill(.white).frame(width: 8, height: 8))
                .overlay(Circle().stroke(.white, lineWidth: 2))
            PinTail().fill(Color(red: 1, green: 0.23, blue: 0.19)).frame(width: 10, height: 9)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .offset(y: -17)
    }

    // 实时共享：她的头像圆圈＋一圈淡蓝光晕
    private var liveMarker: some View {
        ZStack {
            if liveActive { Circle().fill(Color(red: 0.04, green: 0.52, blue: 1).opacity(0.13)).frame(width: 96, height: 96) }
            Group {
                if let img = Self.image(fromDataURL: userAvatar) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(red: 0.96, green: 0.71, blue: 0.86).overlay(Text("霁").font(.system(size: 17, weight: .semibold)).foregroundColor(.white))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .opacity(liveActive ? 1 : 0.7)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isLive {
                HStack {
                    Text("陈霁").font(.system(size: 15, weight: .semibold)).foregroundColor(ink)
                    Spacer()
                    if isUser && liveActive {
                        Button {
                            guard let id = card.shareID, !stopping else { return }
                            stopping = true
                            Task { await PlacesAPI.stop(id); stopping = false }
                        } label: {
                            Text(stopping ? "结束中…" : "结束共享").font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 1, green: 0.23, blue: 0.19))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 5) {
                    Circle().fill(liveActive ? Color(red: 0.2, green: 0.78, blue: 0.35) : Color.gray).frame(width: 7, height: 7)
                    Text(liveActive ? "实时位置 · 共享中" : "实时位置 · 已结束共享")
                }
                .font(.system(size: 12.5)).foregroundColor(dim)
                Text(liveLine).font(.system(size: 12.5)).foregroundColor(dim).lineLimit(2)
            } else {
                Text(card.kind == "current" ? "我的位置" : card.name)
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(ink).lineLimit(2)
                let addr = card.kind == "current" ? (card.address?.isEmpty == false ? card.address! : card.name) : (card.address ?? "")
                if !addr.isEmpty {
                    Text(addr).font(.system(size: 12.5)).foregroundColor(dim).lineLimit(2)
                }
                HStack(spacing: 3) {
                    Image(systemName: "map").font(.system(size: 10))
                    Text("地图")
                }
                .font(.system(size: 11)).foregroundColor(Color(white: 0.56)).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13).padding(.top, 9).padding(.bottom, 11)
    }

    private var liveLine: String {
        let addr = (live?.address.isEmpty == false ? live!.address : (card.address ?? ""))
        var when = ""
        if let ts = live?.ts, let d = Self.parseTS(ts) {
            let mins = Int(Date().timeIntervalSince(d) / 60)
            when = mins < 1 ? "刚刚更新" : (mins < 60 ? "\(mins) 分钟前更新" : "\(mins / 60) 小时前更新")
        }
        return [when, addr].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: center))
        item.name = isLive ? "陈霁" : (card.kind == "current" ? "陈霁的位置" : card.name)
        item.openInMaps(launchOptions: [MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: center)])
    }

    static func parseTS(_ s: String) -> Date? {
        // 后端写的是北京时间、不带时区：2026-10-08T21:00:31
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(s.prefix(19)))
    }

    static func image(fromDataURL raw: String) -> UIImage? {
        guard let comma = raw.firstIndex(of: ","),
              let data = Data(base64Encoded: String(raw[raw.index(after: comma)...])) else { return nil }
        return UIImage(data: data)
    }
}

private struct PinTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 加号里的「位置」：发当前位置 / 共享实时位置 / 搜一个地方

@MainActor
final class PlaceSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
        let around = SensorReporter.shared.lastLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 30.593, longitude: 114.305)    // 没定位就按武汉
        completer.region = MKCoordinateRegion(center: around, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = completer.results
        Task { @MainActor in self.results = r }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}

    func resolve(_ c: MKLocalSearchCompletion) async -> MKMapItem? {
        let res = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start()
        return res?.mapItems.first
    }
}

struct LocationPickerSheet: View {
    /// 拼好的一整条 [LOCATION_CARD]…，交给聊天页照普通文字发
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = PlaceSearchModel()
    @State private var activeShare: String?
    @State private var working = false
    @State private var hint = ""

    var body: some View {
        NavigationStack {
            List {
                if search.query.isEmpty {
                    Section {
                        Button { Task { await sendCurrent() } } label: {
                            row("location.fill", .blue, "发送我的当前位置", nil)
                        }
                        if let id = activeShare {
                            Button(role: .destructive) {
                                Task { working = true; await PlacesAPI.stop(id); activeShare = nil; working = false; dismiss() }
                            } label: {
                                row("location.slash.fill", .red, "结束实时位置共享", "现在正在共享")
                            }
                        } else {
                            Button { Task { await startLive() } } label: {
                                row("location.circle.fill", .green, "共享实时位置", "一直共享，直到你点结束")
                            }
                        }
                    } footer: {
                        if !hint.isEmpty { Text(hint).foregroundColor(.red) }
                    }
                } else {
                    Section {
                        ForEach(search.results, id: \.self) { c in
                            Button { Task { await sendPlace(c) } } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).foregroundColor(.primary)
                                    if !c.subtitle.isEmpty {
                                        Text(c.subtitle).font(.system(size: 13)).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .disabled(working)
            .overlay { if working { ProgressView() } }
            .searchable(text: $search.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索地点")
            .navigationTitle("位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task { activeShare = await PlacesAPI.current()?.id }
        }
        .preferredColorScheme(AlcoveAppearance.isDark ? .dark : .light)
    }

    private func row(_ icon: String, _ tint: Color, _ title: String, _ sub: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundColor(.primary)
                if let sub { Text(sub).font(.system(size: 12.5)).foregroundColor(.secondary) }
            }
        }
        .padding(.vertical, 2)
    }

    private func here() async -> (CLLocationCoordinate2D, String, String)? {
        guard let loc = SensorReporter.shared.lastLocation else { return nil }
        var name = "我的位置", addr = ""
        if let pm = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "zh_CN")).first {
            name = pm.name ?? name
            addr = [pm.administrativeArea, pm.locality, pm.subLocality, pm.thoroughfare, pm.subThoroughfare]
                .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined()
        }
        return (loc.coordinate, name, addr)
    }

    private func sendCurrent() async {
        working = true
        defer { working = false }
        guard let h = await here() else {
            hint = "还没拿到你的位置，开一下定位权限或者等几秒再试"
            return
        }
        let (c, name, addr) = h
        onSend(LocationChatCard.message(kind: "current", name: name, address: addr, coordinate: c))
        dismiss()
    }

    private func startLive() async {
        working = true
        defer { working = false }
        guard let h = await here() else {
            hint = "还没拿到你的位置，开一下定位权限或者等几秒再试"
            return
        }
        let (c, name, addr) = h
        guard let id = await PlacesAPI.start() else {
            hint = "没开成，网络不太好，再点一次"
            return
        }
        UserDefaults.standard.set(id, forKey: "placesLiveShareID")
        NotificationCenter.default.post(name: .placesShareChanged, object: nil)
        onSend(LocationChatCard.message(kind: "live", name: name, address: addr, coordinate: c, shareID: id))
        dismiss()
    }

    private func sendPlace(_ c: MKLocalSearchCompletion) async {
        working = true
        defer { working = false }
        guard let item = await search.resolve(c) else {
            hint = "这个地方没查到坐标，换一个试试"
            return
        }
        let pm = item.placemark
        let addr = [pm.administrativeArea, pm.locality, pm.subLocality, pm.thoroughfare, pm.subThoroughfare]
            .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined()
        onSend(LocationChatCard.message(kind: "place", name: item.name ?? c.title,
                                        address: addr.isEmpty ? c.subtitle : addr, coordinate: pm.coordinate))
        dismiss()
    }
}
