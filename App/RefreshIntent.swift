import AppIntents
import WidgetKit
import Core

/// "Refresh Spindle" — for a Shortcuts automation such as
/// "When Spotify is closed → Refresh Spindle", so the widget catches up within
/// seconds after you change songs inside the Spotify app.
///
/// Runs in the background without opening the app: one Spotify fetch (shared with the
/// widget through the App Group), then a widget reload that reuses it.
struct RefreshSpindleIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Spindle"
    static var description = IntentDescription("Checks what Spotify is playing and updates the Spindle widget.")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        _ = try? await SpotifyService.fetchPlayback()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Makes the action appear in the Shortcuts app (and Siri: "Refresh Spindle").
struct SpindleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshSpindleIntent(),
            phrases: ["Refresh \(.applicationName)"],
            shortTitle: "Refresh Widget",
            systemImageName: "arrow.clockwise")
    }
}
