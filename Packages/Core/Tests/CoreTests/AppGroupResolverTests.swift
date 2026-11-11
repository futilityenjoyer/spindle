import XCTest
@testable import Core

final class AppGroupResolverTests: XCTestCase {
    private let base = "group.dev.spindlevinyl.shared"

    func testUnmodifiedBuildUsesBaseID() {
        let id = AppGroupResolver.resolve(baseID: base, altAppGroups: [], profileGroups: [base]) { $0 == self.base }
        XCTAssertEqual(id, base)
    }

    func testSideStoreRewriteFoundViaProfile() {
        // SideStore appends the team ID and does not write ALTAppGroups.
        let rewritten = base + ".ABCDE12345"
        let id = AppGroupResolver.resolve(baseID: base, altAppGroups: [], profileGroups: [rewritten]) { $0 == rewritten }
        XCTAssertEqual(id, rewritten)
    }

    func testAltStoreRewriteFoundViaInfoPlist() {
        let rewritten = base + ".ABCDE12345"
        let id = AppGroupResolver.resolve(baseID: base, altAppGroups: [rewritten], profileGroups: []) { $0 == rewritten }
        XCTAssertEqual(id, rewritten)
    }

    func testPrefersOurGroupOverUnrelatedOnes() {
        let ours = base + ".TEAM"
        let id = AppGroupResolver.resolve(baseID: base, altAppGroups: [], profileGroups: ["group.someone.else", ours]) { _ in true }
        XCTAssertEqual(id, ours)
    }

    func testUnrelatedGroupUsedOnlyAsLastResort() {
        let id = AppGroupResolver.resolve(baseID: base, altAppGroups: [], profileGroups: ["group.renamed.by.tool"]) {
            $0 == "group.renamed.by.tool"
        }
        XCTAssertEqual(id, "group.renamed.by.tool")
    }

    func testNilWhenNothingUsable() {
        XCTAssertNil(AppGroupResolver.resolve(baseID: base, altAppGroups: [], profileGroups: [base + ".X"]) { _ in false })
    }

    func testLookalikePrefixIsNotTreatedAsOurs() {
        // "…sharedextra" must not count as derived from "…shared".
        let lookalike = base + "extra"
        let ours = base + ".TEAM"
        let id = AppGroupResolver.resolve(baseID: base, altAppGroups: [lookalike], profileGroups: [ours]) { _ in true }
        XCTAssertEqual(id, ours)
    }
}
