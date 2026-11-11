import Foundation
import XCTest
@testable import Core
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TimelinePlannerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func track(_ title: String, seconds: Int) -> PlayableItem {
        PlayableItem(kind: .track, id: title, uri: nil, title: title, subtitle: "Artist", albumName: nil,
                     durationMs: seconds * 1000, isLocal: false, images: [])
    }

    private func snapshot(playing: Bool = true, current: PlayableItem?, progressSeconds: Int = 0,
                          queue: [PlayableItem] = [], fetchedAt: Date? = nil, kind: NowPlaying.Kind = .track) -> PlaybackSnapshot {
        PlaybackSnapshot(
            fetchedAt: fetchedAt ?? t0,
            nowPlaying: NowPlaying(kind: kind, isPlaying: playing, progressMs: progressSeconds * 1000, item: current),
            queue: queue)
    }

    func testNothingPlayingIsIdleForAnHour() {
        let plan = TimelinePlanner.plan(PlaybackSnapshot(fetchedAt: t0, nowPlaying: nil, queue: []), now: t0, lowPower: false)
        XCTAssertEqual(plan.entries, [PlannedEntry(date: t0, item: nil, isPlaying: false)])
        XCTAssertEqual(plan.reloadAt, t0.addingTimeInterval(3600))
    }

    func testPausedShowsStillRecordAndChecksEvery30Minutes() {
        let a = track("A", seconds: 200)
        let plan = TimelinePlanner.plan(snapshot(playing: false, current: a), now: t0, lowPower: false)
        XCTAssertEqual(plan.entries.count, 1)
        XCTAssertEqual(plan.entries[0].item, a)
        XCTAssertFalse(plan.entries[0].isPlaying)
        XCTAssertEqual(plan.reloadAt, t0.addingTimeInterval(1800))
    }

    func testPredictsQueueBoundariesThenStopsAtLastSeen() {
        let a = track("A", seconds: 200), b = track("B", seconds: 180), c = track("C", seconds: 240), d = track("D", seconds: 200)
        // 150 s into A: B starts at +50 s, C at +230 s, D at +470 s; reload at +600, last seen at +720.
        let plan = TimelinePlanner.plan(snapshot(current: a, progressSeconds: 150, queue: [b, c, d]), now: t0, lowPower: false)

        XCTAssertEqual(plan.reloadAt, t0.addingTimeInterval(600))
        XCTAssertEqual(plan.entries.map(\.item?.title), ["A", "B", "C", "D", "D"])
        XCTAssertEqual(plan.entries.map(\.date), [t0, t0 + 50, t0 + 230, t0 + 470, t0 + 720])
        XCTAssertEqual(plan.entries.map(\.isPlaying), [true, true, true, true, false])
        XCTAssertEqual(plan.entries.last?.isStale, true)
    }

    func testStopsPredictingAtTheLastSeenTime() {
        let a = track("A", seconds: 100), long = track("Long", seconds: 3600), after = track("After", seconds: 100)
        let plan = TimelinePlanner.plan(snapshot(current: a, queue: [long, after]), now: t0, lowPower: false)
        // Long starts at +100 s and runs past the 720 s last-seen point, so "After" is never planned.
        XCTAssertEqual(plan.entries.map(\.item?.title), ["A", "Long", "Long"])
    }

    func testOldSnapshotAdvancesToTheTrackThatIsActuallyPlaying() {
        let a = track("A", seconds: 100), b = track("B", seconds: 300)
        // Fetched 50 s ago at 90 s of 100 s, so A ended 40 s ago and B is playing now.
        let plan = TimelinePlanner.plan(snapshot(current: a, progressSeconds: 90, queue: [b], fetchedAt: t0 - 50),
                                        now: t0, lowPower: false)
        XCTAssertEqual(plan.entries.first?.item?.title, "B")
        XCTAssertEqual(plan.entries.first?.date, t0)
    }

    func testLowPowerModeReloadsLessOften() {
        let plan = TimelinePlanner.plan(snapshot(current: track("A", seconds: 200)), now: t0, lowPower: true)
        XCTAssertEqual(plan.reloadAt, t0.addingTimeInterval(900))
        XCTAssertEqual(plan.entries.last?.date, t0.addingTimeInterval(1020))
    }

    func testUnknownDurationStopsPrediction() {
        let a = track("A", seconds: 10), mystery = track("?", seconds: 0), later = track("Later", seconds: 10)
        let plan = TimelinePlanner.plan(snapshot(current: a, queue: [mystery, later]), now: t0, lowPower: false)
        XCTAssertEqual(plan.entries.map(\.item?.title), ["A", "?", "?"])
    }

    func testAdvertisementSpinsWithoutAnItem() {
        let plan = TimelinePlanner.plan(snapshot(current: nil, kind: .ad), now: t0, lowPower: false)
        XCTAssertTrue(plan.entries[0].isAdvertisement)
        XCTAssertTrue(plan.entries[0].isPlaying)
        XCTAssertNil(plan.entries[0].item)
        XCTAssertTrue(plan.entries.last?.isStale ?? false)
    }

    func testPlayerCommandRequests() {
        let pause = SpotifyAPI.commandRequest(.pause, accessToken: "t")
        XCTAssertEqual(pause.httpMethod, "PUT")
        XCTAssertEqual(pause.url?.absoluteString, "https://api.spotify.com/v1/me/player/pause")
        XCTAssertEqual(pause.httpBody, Data())
        XCTAssertEqual(pause.value(forHTTPHeaderField: "Authorization"), "Bearer t")

        XCTAssertEqual(SpotifyAPI.commandRequest(.play, accessToken: "t").url?.path, "/v1/me/player/play")
        let next = SpotifyAPI.commandRequest(.next, accessToken: "t")
        XCTAssertEqual(next.httpMethod, "POST")
        XCTAssertEqual(next.url?.path, "/v1/me/player/next")
        let previous = SpotifyAPI.commandRequest(.previous, accessToken: "t")
        XCTAssertEqual(previous.httpMethod, "POST")
        XCTAssertEqual(previous.url?.path, "/v1/me/player/previous")
    }
}
