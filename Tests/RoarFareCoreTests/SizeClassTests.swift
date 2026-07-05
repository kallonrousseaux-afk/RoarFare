import XCTest
@testable import RoarFareCore

final class SizeClassTests: XCTestCase {
    func testBlockingUnitCosts() {
        // GAME_DESIGN.md §4's BU table — the core differentiator's numbers.
        XCTAssertEqual(SizeClass.tiny.blockingUnits, 1)
        XCTAssertEqual(SizeClass.small.blockingUnits, 2)
        XCTAssertEqual(SizeClass.medium.blockingUnits, 3)
        XCTAssertEqual(SizeClass.large.blockingUnits, 5)
        XCTAssertEqual(SizeClass.apex.blockingUnits, 8)
    }
}
