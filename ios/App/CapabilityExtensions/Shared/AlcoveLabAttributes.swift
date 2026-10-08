import ActivityKit
import AppIntents
import Foundation

struct AlcoveLabAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var message: String
        var startedAt: Date
        var bpm: Int
    }

    var name: String
}

// MARK: - 1008 通话灵动岛 / 锁屏条
// 她给的参考：黑色灵动岛＋左边头像＋名字＋「通话中 · 计时」＋右边两个圆按钮（消息、免提）。
// 系统 CallKit 那套的按钮是苹果定死的，换不了，所以自己画一个 Live Activity。

struct CallActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var speakerOn: Bool
    }

    var name: String
    /// 头像缩成小 JPEG 塞进来：小组件是另一个进程，拿不到 App 里存的头像（没开 App Group）；ActivityKit 总共只给 4KB
    var avatarJPEG: Data?
}

/// 按钮的动作只在 App 进程里真正执行（LiveActivityIntent 跑在 App 里）；通话页开着时把这两个口子接上，挂断清掉。
/// 小组件进程里这两个是 nil，什么都不做。
enum CallActivityBridge {
    static var toggleSpeaker: (() -> Void)?
    static var askMessage: (() -> Void)?
}

struct CallSpeakerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "免提"

    @MainActor
    func perform() async throws -> some IntentResult {
        CallActivityBridge.toggleSpeaker?()
        return .result()
    }
}

struct CallMessageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "给他说句话"

    @MainActor
    func perform() async throws -> some IntentResult {
        CallActivityBridge.askMessage?()
        return .result()
    }
}
