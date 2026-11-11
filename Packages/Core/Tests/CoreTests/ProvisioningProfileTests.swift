import Foundation
import XCTest
@testable import Core

final class ProvisioningProfileTests: XCTestCase {
    /// Mimics a real profile: binary CMS header + XML plist + binary trailer.
    private func profileBytes(groups: [String], team: String, expiry: String) -> Data {
        let groupXML = groups.map { "<string>\($0)</string>" }.joined()
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Name</key><string>Spindle free profile</string>
          <key>TeamIdentifier</key><array><string>\(team)</string></array>
          <key>ExpirationDate</key><date>\(expiry)</date>
          <key>Entitlements</key><dict>
            <key>com.apple.security.application-groups</key><array>\(groupXML)</array>
          </dict>
        </dict></plist>
        """
        return Data([0x30, 0x82, 0x1F, 0x00, 0x06, 0x09]) + Data(xml.utf8) + Data([0xA0, 0x82, 0x00, 0xFF])
    }

    func testParsesGroupsTeamAndExpiry() throws {
        let data = profileBytes(groups: ["group.dev.spindlevinyl.shared.ABCDE12345"], team: "ABCDE12345", expiry: "2026-11-18T10:00:00Z")
        let profile = try XCTUnwrap(ProvisioningProfile.parse(data))

        XCTAssertEqual(profile.name, "Spindle free profile")
        XCTAssertEqual(profile.teamID, "ABCDE12345")
        XCTAssertEqual(profile.appGroups, ["group.dev.spindlevinyl.shared.ABCDE12345"])
        XCTAssertEqual(profile.expirationDate, ISO8601DateFormatter().date(from: "2026-11-18T10:00:00Z"))
    }

    func testDaysUntilExpiry() throws {
        let profile = try XCTUnwrap(ProvisioningProfile.parse(
            profileBytes(groups: [], team: "T", expiry: "2026-11-18T10:00:00Z")))
        let formatter = ISO8601DateFormatter()

        XCTAssertEqual(profile.daysUntilExpiry(from: try XCTUnwrap(formatter.date(from: "2026-11-11T10:00:00Z"))), 7)
        XCTAssertEqual(profile.daysUntilExpiry(from: try XCTUnwrap(formatter.date(from: "2026-11-16T12:00:00Z"))), 1)
        XCTAssertEqual(profile.daysUntilExpiry(from: try XCTUnwrap(formatter.date(from: "2026-11-19T10:00:00Z"))), -1)
    }

    func testReturnsNilWithoutPlist() {
        XCTAssertNil(ProvisioningProfile.parse(Data([0x00, 0x01, 0x02])))
        XCTAssertNil(ProvisioningProfile.parse(Data("<?xml no end".utf8)))
    }

    func testMissingEntitlementsGivesNoGroups() throws {
        let xml = #"<?xml version="1.0"?><plist version="1.0"><dict><key>Name</key><string>x</string></dict></plist>"#
        let profile = try XCTUnwrap(ProvisioningProfile.parse(Data(xml.utf8)))
        XCTAssertEqual(profile.appGroups, [])
        XCTAssertNil(profile.teamID)
        XCTAssertNil(profile.daysUntilExpiry(from: Date()))
    }
}
