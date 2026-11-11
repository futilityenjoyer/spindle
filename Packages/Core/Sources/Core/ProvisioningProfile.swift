import Foundation

/// The parts of an `embedded.mobileprovision` the app needs at runtime.
///
/// Sideloading tools (SideStore, AltStore, Sideloadly) re-sign the app with a free
/// Apple ID and write a fresh profile into every bundle. That profile tells us the
/// App Group we were *actually* granted (often rewritten to `<group>.<TEAMID>`) and
/// when the 7-day signature expires.
///
/// The file is a CMS-signed blob wrapping an XML plist. We only read our own bundle,
/// so we extract the plist by byte search instead of verifying the CMS signature.
public struct ProvisioningProfile: Equatable, Sendable {
    public var name: String?
    public var teamID: String?
    public var appGroups: [String]
    public var expirationDate: Date?

    public init(name: String? = nil, teamID: String? = nil, appGroups: [String] = [], expirationDate: Date? = nil) {
        self.name = name
        self.teamID = teamID
        self.appGroups = appGroups
        self.expirationDate = expirationDate
    }

    /// Parses the raw bytes of an `embedded.mobileprovision`. Returns nil if no plist is found.
    public static func parse(_ data: Data) -> ProvisioningProfile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }

        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = (try? PropertyListSerialization.propertyList(from: plistData, format: nil)) as? [String: Any]
        else { return nil }

        let entitlements = plist["Entitlements"] as? [String: Any]
        return ProvisioningProfile(
            name: plist["Name"] as? String,
            teamID: (plist["TeamIdentifier"] as? [String])?.first,
            appGroups: entitlements?["com.apple.security.application-groups"] as? [String] ?? [],
            expirationDate: plist["ExpirationDate"] as? Date
        )
    }

    /// Whole days left before the signature expires (negative once expired), or nil if unknown.
    public func daysUntilExpiry(from now: Date) -> Int? {
        guard let expirationDate else { return nil }
        return Int((expirationDate.timeIntervalSince(now) / 86_400).rounded(.down))
    }
}
