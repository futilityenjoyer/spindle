import Foundation
import Core

/// The App Group shared by the app and the widget, discovered at runtime.
/// Compiled into both targets so they resolve the same group the same way.
enum AppGroup {
    /// The group as authored in project.yml (also stored in each Info.plist).
    static let baseID: String =
        Bundle.main.object(forInfoDictionaryKey: "SpindleAppGroupBaseID") as? String
        ?? "group.dev.spindlevinyl.shared"

    /// This bundle's embedded provisioning profile (present on sideloaded builds).
    static let profile: ProvisioningProfile? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return ProvisioningProfile.parse(data)
    }()

    /// Groups AltStore writes into Info.plist after re-signing (other tools don't).
    static let altAppGroups: [String] =
        Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []

    /// The group this binary can actually use, or nil if none works (App Group lost in signing).
    static let id: String? = AppGroupResolver.resolve(
        baseID: baseID,
        altAppGroups: altAppGroups,
        profileGroups: profile?.appGroups ?? [],
        isUsable: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    )

    static var containerURL: URL? {
        id.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    /// One-line status for screens with little room (the widget).
    static var shortStatus: String {
        if id != nil { return "Shared folder ✓" }
        let count = profile?.appGroups.count ?? 0
        return profile == nil ? "No group · no profile" : "No group · profile lists \(count)"
    }
}

extension Array where Element == String {
    /// "a, b" or "none" — for Diagnostics rows.
    var listOrNone: String { isEmpty ? "none" : joined(separator: ", ") }
}
