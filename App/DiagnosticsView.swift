import AuthenticationServices
import SwiftUI
import WidgetKit
import Core

/// Setup and diagnostics: connect Spotify, see what the widget sees, and confirm the
/// install works without a Mac. Long-press any value to copy it.
struct DiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var heartbeats: [WidgetHeartbeat] = []
    @State private var spotify: SpotifyState = .checking
    @State private var isWorking = false
    @State private var labelImage: CGImage?
    @State private var palette: ArtPalette = .neutral
    @State private var responsive: Bool = SharedSettings.responsiveUpdates

    enum SpotifyState {
        case checking
        case signedOut(note: String?)
        case connected(PlaybackSnapshot)
        case problem(String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Still preview of the small widget's record with the current cover.
                    VinylRecord(style: .inscribed, art: labelImage, palette: palette,
                                labelFraction: 0.6, rotation: EmptyModifier.identity)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Color(rgb: palette.surfaceDark))
                }

                spotifySection

                Section {
                    Toggle("Responsive updates", isOn: $responsive)
                } header: {
                    Text("Widget")
                } footer: {
                    Text("Checks Spotify every 5 minutes while playing instead of 10. Fresher, but iOS's daily refresh allowance runs out after fewer listening hours.")
                }
                .onChange(of: responsive) { _, isOn in
                    SharedSettings.responsiveUpdates = isOn
                    WidgetCenter.shared.reloadAllTimelines()
                }

                Section {
                    Text("1. Open the **Shortcuts** app → **Automation** → **+**.")
                    Text("2. Choose **App**, pick **Spotify**, tick **Is Closed**, and choose **Run Immediately**.")
                    Text("3. Add the action **Refresh Spindle**, then **Done**.")
                } header: {
                    Text("Refresh when you leave Spotify")
                } footer: {
                    Text("After you change songs inside the Spotify app, the widget catches up as soon as you leave it.")
                }

                Section("Widget status") {
                    if let latest = heartbeats.last {
                        row("Last widget refresh", latest.date.formatted(date: .abbreviated, time: .standard))
                        row("Widget built with", xcodeName(latest.xcode))
                        row("Spin effect type", latest.spinEffectTypePresent ? "Present" : "Missing ❌")
                        row("Refreshes logged", "\(heartbeats.count)")
                    } else {
                        Text("No widget heartbeat yet. Add the **Spindle** widget to your Home Screen, then come back.")
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
            .refreshable { await refreshAll(force: true) }
        }
        .task { await refreshAll(force: false) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshAll(force: false) } }
        }
    }

    // MARK: Spotify

    @ViewBuilder
    private var spotifySection: some View {
        Section("Spotify") {
            switch spotify {
            case .checking:
                HStack { ProgressView(); Text("Checking…").foregroundStyle(.secondary) }

            case .signedOut(let note):
                if let note { Text(note).foregroundStyle(.secondary) }
                Button {
                    Task { await connect() }
                } label: {
                    Label("Connect Spotify", systemImage: "music.note")
                }
                .disabled(isWorking)

            case .connected(let snapshot):
                nowPlayingRows(snapshot)
                row("Last fetched", snapshot.fetchedAt.formatted(date: .omitted, time: .standard))
                Button("Refresh now") { Task { await refreshAll(force: true) } }
                    .disabled(isWorking)
                Button("Disconnect Spotify", role: .destructive) {
                    SpotifyService.signOut()
                    WidgetCenter.shared.reloadAllTimelines()
                    labelImage = nil
                    palette = .neutral
                    spotify = .signedOut(note: nil)
                }

            case .problem(let message):
                Text(message).foregroundStyle(.secondary)
                Button("Try again") { Task { await refreshAll(force: true) } }
                    .disabled(isWorking)
                Button("Disconnect Spotify", role: .destructive) {
                    SpotifyService.signOut()
                    WidgetCenter.shared.reloadAllTimelines()
                    labelImage = nil
                    palette = .neutral
                    spotify = .signedOut(note: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func nowPlayingRows(_ snapshot: PlaybackSnapshot) -> some View {
        if let now = snapshot.nowPlaying {
            let status = now.isPlaying ? "Playing" : "Paused"
            if let item = now.item {
                row(status, "\(item.title) — \(item.subtitle)")
            } else {
                row(status, now.kind == .ad ? "Advertisement" : "Unavailable (private session?)")
            }
        } else {
            row("Now playing", "Nothing")
        }
        if !snapshot.queue.isEmpty {
            row("Up next", snapshot.queue.prefix(3).map(\.title).joined(separator: " · "))
        }
    }

    @MainActor
    private func connect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await SpotifyLogin.signIn(using: webAuthenticationSession)
            await refreshSpotify(force: true)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User closed the sign-in sheet; nothing to report.
        } catch let failure as SpotifyService.Failure {
            spotify = .problem(failure.explanation)
        } catch {
            spotify = .problem(error.localizedDescription)
        }
    }

    /// One fetch when the app opens (and on pull-to-refresh). The result is shared with
    /// the widget, and reloading the widget while the app is open doesn't use its budget.
    @MainActor
    private func refreshSpotify(force: Bool) async {
        if !force, case .connected(let snapshot) = spotify, snapshot.isFresh(now: Date(), maxAge: 15) {
            return   // just fetched; don't wake the radio again
        }
        do {
            guard try TokenStore.load() != nil else {
                spotify = .signedOut(note: nil)
                return
            }
        } catch {
            spotify = .problem(SpotifyService.Failure.waitingForUnlock.explanation)
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let snapshot = try await SpotifyService.fetchPlayback()
            spotify = .connected(snapshot)
            if let item = snapshot.nowPlaying?.item, let remote = ArtworkCache.remoteURL(for: item) {
                labelImage = await ArtworkCache.images(for: [item], maxPixelSize: 660)[remote]
            } else {
                labelImage = nil
            }
            palette = labelImage.map { ArtPaletteExtractor.palette(from: $0) } ?? .neutral
            // Reloads requested while the app is open don't use the widget's daily budget.
            WidgetCenter.shared.reloadAllTimelines()
        } catch SpotifyService.Failure.notSignedIn {
            spotify = .signedOut(note: nil)
        } catch SpotifyService.Failure.api(.invalidGrant) {
            spotify = .signedOut(note: SpotifyService.Failure.api(.invalidGrant).explanation)
        } catch let failure as SpotifyService.Failure {
            spotify = .problem(failure.explanation)
        } catch {
            spotify = .problem(error.localizedDescription)
        }
    }

    @MainActor
    private func refreshAll(force: Bool) async {
        heartbeats = SharedStore.loadHeartbeats()
        await refreshSpotify(force: force)
        heartbeats = SharedStore.loadHeartbeats()
    }

    // MARK: Helpers

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
