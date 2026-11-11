import Foundation
import XCTest
@testable import Core

final class SpotifyParsingTests: XCTestCase {
    private let trackJSON = """
    {
      "is_playing": true,
      "progress_ms": 61000,
      "currently_playing_type": "track",
      "item": {
        "id": "t1", "uri": "spotify:track:t1", "name": "Low Sun Over Harbour", "type": "track",
        "duration_ms": 215000, "is_local": false,
        "artists": [{"name": "Harbour Lights"}, {"name": "Guest"}],
        "album": {"name": "Tides", "images": [
          {"url": "https://i.scdn.co/640", "width": 640, "height": 640},
          {"url": "https://i.scdn.co/300", "width": 300, "height": 300},
          {"url": "https://i.scdn.co/64", "width": 64, "height": 64}
        ]}
      }
    }
    """

    func testParsesTrack() throws {
        let now = try SpotifyParser.nowPlaying(from: Data(trackJSON.utf8))
        XCTAssertEqual(now.kind, .track)
        XCTAssertTrue(now.isPlaying)
        XCTAssertEqual(now.progressMs, 61000)
        let item = try XCTUnwrap(now.item)
        XCTAssertEqual(item.title, "Low Sun Over Harbour")
        XCTAssertEqual(item.subtitle, "Harbour Lights, Guest")
        XCTAssertEqual(item.albumName, "Tides")
        XCTAssertEqual(item.durationMs, 215000)
        XCTAssertEqual(item.kind, .track)
        XCTAssertEqual(item.images.count, 3)
    }

    func testImageSelection() throws {
        let item = try XCTUnwrap(try SpotifyParser.nowPlaying(from: Data(trackJSON.utf8)).item)
        XCTAssertEqual(item.image(minWidth: 200)?.url, "https://i.scdn.co/300")
        XCTAssertEqual(item.image(minWidth: 400)?.url, "https://i.scdn.co/640")
        XCTAssertEqual(item.image(minWidth: 2000)?.url, "https://i.scdn.co/640") // largest as fallback
    }

    func testParsesEpisodeUsingShowName() throws {
        let json = """
        {"is_playing": false, "progress_ms": 5, "currently_playing_type": "episode",
         "item": {"name": "Ep 12", "type": "episode", "duration_ms": 3600000,
                  "images": [{"url": "https://i.scdn.co/ep", "width": 300, "height": 300}],
                  "show": {"name": "Deep Grooves Podcast", "images": []}}}
        """
        let now = try SpotifyParser.nowPlaying(from: Data(json.utf8))
        XCTAssertEqual(now.kind, .episode)
        XCTAssertFalse(now.isPlaying)
        XCTAssertEqual(now.item?.subtitle, "Deep Grooves Podcast")
        XCTAssertEqual(now.item?.images.first?.url, "https://i.scdn.co/ep")
    }

    func testAdHasNoItem() throws {
        let json = #"{"is_playing": true, "currently_playing_type": "ad", "item": null}"#
        let now = try SpotifyParser.nowPlaying(from: Data(json.utf8))
        XCTAssertEqual(now.kind, .ad)
        XCTAssertNil(now.item)
    }

    func testLocalFileWithoutArtwork() throws {
        let json = """
        {"is_playing": true, "currently_playing_type": "track",
         "item": {"name": "Home Demo", "type": "track", "is_local": true, "duration_ms": 1000,
                  "artists": [{"name": "Me"}], "album": {"name": "", "images": []}}}
        """
        let item = try XCTUnwrap(try SpotifyParser.nowPlaying(from: Data(json.utf8)).item)
        XCTAssertTrue(item.isLocal)
        XCTAssertNil(item.image(minWidth: 100))
    }

    func testParsesQueueInOrder() throws {
        let json = """
        {"currently_playing": {"name": "Now"},
         "queue": [{"name": "Next", "type": "track", "artists": [{"name": "A"}]},
                   {"name": "After", "type": "track", "artists": [{"name": "B"}]}]}
        """
        let queue = try SpotifyParser.queue(from: Data(json.utf8))
        XCTAssertEqual(queue.map(\.title), ["Next", "After"])
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try SpotifyParser.nowPlaying(from: Data("<html>".utf8)))
        XCTAssertThrowsError(try SpotifyParser.queue(from: Data("[]".utf8)))
    }

    func testSnapshotFreshnessAndRoundTrip() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let snapshot = PlaybackSnapshot(fetchedAt: now, nowPlaying: nil, queue: [])
        XCTAssertTrue(snapshot.isFresh(now: now.addingTimeInterval(59)))
        XCTAssertFalse(snapshot.isFresh(now: now.addingTimeInterval(61)))
        XCTAssertEqual(PlaybackSnapshot.decode(try PlaybackSnapshot.encode(snapshot)), snapshot)
    }
}
