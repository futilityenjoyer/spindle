import AppIntents
import WidgetKit
import Core

// Widget buttons. Each tap runs here, in the widget extension, and iOS always reloads
// the widget afterwards — without using the daily reload budget. That makes anything
// you do from the widget show up immediately. (Buttons don't work while the phone is
// locked; iOS requires Face ID first.)

struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Play or Pause"
    static var description = IntentDescription("Plays or pauses Spotify.")

    @Parameter(title: "Currently Playing")
    var isPlaying: Bool

    init() {}

    init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    func perform() async throws -> some IntentResult {
        try? await SpotifyService.perform(isPlaying ? .pause : .play)
        // Give Spotify a moment so the reload that follows sees the new state.
        try? await Task.sleep(nanoseconds: 500_000_000)
        return .result()
    }
}

struct SkipTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    static var description = IntentDescription("Skips to the next track on Spotify.")

    init() {}

    func perform() async throws -> some IntentResult {
        try? await SpotifyService.perform(.next)
        // Spotify reports the new track after a short lag.
        try? await Task.sleep(nanoseconds: 800_000_000)
        return .result()
    }
}
