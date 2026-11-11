import Foundation

/// A record written by the widget each time iOS asks it for a timeline.
/// The app shows these in Diagnostics: proof that the widget runs, that the App Group
/// is shared, how often iOS reloads it, and which Xcode built the widget.
public struct WidgetHeartbeat: Codable, Equatable, Sendable {
    public var date: Date
    public var family: String
    /// `DTXcode` from the widget's Info.plist, e.g. "2660" for Xcode 26.6.
    public var xcode: String?
    /// Whether the private rotation effect's type was found in this process.
    /// (Presence of the type does not prove it renders — the device test does.)
    public var spinEffectTypePresent: Bool

    public init(date: Date, family: String, xcode: String?, spinEffectTypePresent: Bool) {
        self.date = date
        self.family = family
        self.xcode = xcode
        self.spinEffectTypePresent = spinEffectTypePresent
    }

    /// Appends `beat`, keeping only the newest `limit` entries.
    public static func appending(_ beat: WidgetHeartbeat, to log: [WidgetHeartbeat], limit: Int = 50) -> [WidgetHeartbeat] {
        Array((log + [beat]).suffix(max(limit, 0)))
    }

    public static func encode(_ log: [WidgetHeartbeat]) throws -> Data {
        try JSONEncoder().encode(log)
    }

    /// Decodes a stored log; a missing or corrupt file is treated as an empty log.
    public static func decode(_ data: Data) -> [WidgetHeartbeat] {
        (try? JSONDecoder().decode([WidgetHeartbeat].self, from: data)) ?? []
    }
}
