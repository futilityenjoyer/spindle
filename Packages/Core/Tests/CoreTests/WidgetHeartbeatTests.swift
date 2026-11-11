import Foundation
import XCTest
@testable import Core

final class WidgetHeartbeatTests: XCTestCase {
    private func beat(_ seconds: TimeInterval) -> WidgetHeartbeat {
        WidgetHeartbeat(date: Date(timeIntervalSinceReferenceDate: seconds), family: "systemSmall", xcode: "2660", spinEffectTypePresent: true)
    }

    func testAppendingKeepsNewestWithinLimit() {
        var log: [WidgetHeartbeat] = []
        for i in 0..<5 { log = WidgetHeartbeat.appending(beat(TimeInterval(i)), to: log, limit: 3) }
        XCTAssertEqual(log.map(\.date.timeIntervalSinceReferenceDate), [2, 3, 4])
    }

    func testRoundTrip() throws {
        let log = [beat(1.25), beat(800_000_000.5)]
        XCTAssertEqual(WidgetHeartbeat.decode(try WidgetHeartbeat.encode(log)), log)
    }

    func testCorruptDataDecodesToEmpty() {
        XCTAssertEqual(WidgetHeartbeat.decode(Data("not json".utf8)), [])
    }
}
