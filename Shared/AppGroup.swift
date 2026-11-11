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

    /// The group this binary can actually use, or nil if none works (App Group lost in signing).
    static let id: String? = AppGroupResolver.resolve(
        baseID: baseID,
        altAppGroups: Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? [],
        profileGroups: profile?.appGroups ?? [],
        isUsable: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    )

    static var containerURL: URL? {
        id.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }
}
