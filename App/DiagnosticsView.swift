import SwiftUI
import WidgetKit
import Core

/// M0 screen: everything needed to confirm the install works without a Mac.
/// Long-press any value to copy it (e.g. the bundle ID for the Spotify dashboard).
struct DiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var heartbeats: [WidgetHeartbeat] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ZStack {
                        VinylDisc()
                        VinylSheen()
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Widget") {
                    if let latest = heartbeats.last {
                        row("Last widget refresh", latest.date.formatted(date: .abbreviated, time: .standard))
                        row("Widget built with", xcodeName(latest.xcode))
                        row("Spin effect type", latest.spinEffectTypePresent ? "Present" : "Missing ❌")
                        row("Refreshes logged", "\(heartbeats.count)")
                    } else {
                        Text("No widget heartbeat yet. Add the **Spin test** widget to your Home Screen, then come back.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Reload widget now") {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }

                Section("App Group") {
                    row("Authored ID", AppGroup.baseID)
                    row("Resolved ID", AppGroup.id ?? "Not found ❌")
                    row("Shared folder", AppGroup.containerURL == nil ? "Unavailable ❌" : "OK ✅")
                    // What the re-signing tool actually granted — tells us why a group is missing.
                    row("Groups in profile", AppGroup.profile?.appGroups.listOrNone ?? "no profile")
                    row("ALTAppGroups", AppGroup.altAppGroups.listOrNone)
                    row("Profile name", AppGroup.profile?.name ?? "—")
                }

                Section("Install") {
                    row("Bundle ID", Bundle.main.bundleIdentifier ?? "—")
                    row("Team ID", AppGroup.profile?.teamID ?? "—")
                    row("Signature expires", expiryText)
                    row("App built with", xcodeName(Bundle.main.object(forInfoDictionaryKey: "DTXcode") as? String))
                    row("SDK", Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String ?? "—")
                    row("iOS", ProcessInfo.processInfo.operatingSystemVersionString)
                    row("Version", "\(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
                }
            }
            .navigationTitle("Spindle")
            .refreshable { refresh() }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    private func refresh() {
        heartbeats = SharedStore.loadHeartbeats()
    }

    private var expiryText: String {
        guard let profile = AppGroup.profile, let date = profile.expirationDate else {
            return "No profile found"
        }
        let days = profile.daysUntilExpiry(from: Date()) ?? 0
        let when = date.formatted(date: .abbreviated, time: .shortened)
        return days < 0 ? "Expired \(when) ❌" : "\(when) (\(days) d)\(days <= 2 ? " ⚠️" : "")"
    }

    /// "2660" → "Xcode 26.6 (2660)"; DTXcode encodes major/minor/patch as digits.
    private func xcodeName(_ raw: String?) -> String {
        guard let raw, raw.count == 4, let major = Int(raw.prefix(2)) else { return raw ?? "—" }
        let minor = raw.dropFirst(2).prefix(1)
        let patch = raw.suffix(1)
        return "Xcode \(major).\(minor)\(patch == "0" ? "" : ".\(patch)") (\(raw))"
    }

    private func info(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "—"
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
