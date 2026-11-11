import Foundation
import Core

/// Files in the App Group container, readable by both the app and the widget.
enum SharedStore {
    private static var heartbeatURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("heartbeats.json")
    }

    static func loadHeartbeats() -> [WidgetHeartbeat] {
        guard let url = heartbeatURL, let data = try? Data(contentsOf: url) else { return [] }
        return WidgetHeartbeat.decode(data)
    }

    /// Called by the widget each time iOS asks it for a timeline.
    static func recordHeartbeat(family: String) {
        guard let url = heartbeatURL else { return }
        let beat = WidgetHeartbeat(
            date: Date(),
            family: family,
            xcode: Bundle.main.object(forInfoDictionaryKey: "DTXcode") as? String,
            spinEffectTypePresent: SpinEffectProbe.isTypePresent
        )
        let log = WidgetHeartbeat.appending(beat, to: loadHeartbeats())
        guard let data = try? WidgetHeartbeat.encode(log) else { return }
        // Readable while the phone is locked (after first unlock), which widgets need.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Checks whether WidgetKit's private clock-hand rotation type exists in this process.
/// ClockHandKit looks up the same mangled name. The type being present doesn't prove
/// the effect renders — that is what the on-device spin test is for.
enum SpinEffectProbe {
    static var isTypePresent: Bool {
        _typeByName("9WidgetKit24_ClockHandRotationEffectV") != nil
    }
}
