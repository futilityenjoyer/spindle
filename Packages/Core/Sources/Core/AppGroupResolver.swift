/// Works out which App Group this signed binary can actually use.
///
/// We author `group.dev.spindlevinyl.shared`, but re-signers rewrite it:
/// AltStore and SideStore append `.<TEAMID>`; Sideloadly's behaviour is undocumented.
/// The app and the widget are re-signed in the same pass, so they receive the same
/// rewritten group — they just have to discover it the same way. Both call this.
public enum AppGroupResolver {
    /// - Parameters:
    ///   - baseID: the group as authored in project.yml.
    ///   - altAppGroups: `ALTAppGroups` from Info.plist (written by AltStore only).
    ///   - profileGroups: groups listed in the bundle's embedded provisioning profile.
    ///   - isUsable: true if iOS hands out a container for this group
    ///     (`containerURL(forSecurityApplicationGroupIdentifier:)` is non-nil).
    /// - Returns: the first usable candidate, preferring ones derived from `baseID`.
    public static func resolve(
        baseID: String,
        altAppGroups: [String],
        profileGroups: [String],
        isUsable: (String) -> Bool
    ) -> String? {
        var seen = Set<String>()
        let candidates = (altAppGroups + profileGroups + [baseID]).filter { seen.insert($0).inserted }

        func isOurs(_ group: String) -> Bool { group == baseID || group.hasPrefix(baseID + ".") }
        let ordered = candidates.filter(isOurs) + candidates.filter { !isOurs($0) }

        return ordered.first(where: isUsable)
    }
}
