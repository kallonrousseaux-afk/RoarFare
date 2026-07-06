import XCTest
@testable import RoarFareCore

final class LaneDeploymentTests: XCTestCase {
    private func makeUnit(id: String, sizeClass: SizeClass) -> UnitDefinition {
        UnitDefinition(
            id: id,
            name: id,
            era: .cretaceous,
            sizeClass: sizeClass,
            rarity: .common,
            deployCost: 100,
            baseStats: UnitStats(maxHP: 100, attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 1.0)
        )
    }

    func testApexPlusTinyFitsExactlyAtCap() {
        let lane = Lane()
        let apex = makeUnit(id: "apex", sizeClass: .apex) // 8 BU
        let tiny = makeUnit(id: "tiny", sizeClass: .tiny)  // 1 BU

        XCTAssertTrue(lane.deploy(apex, to: .player))
        XCTAssertTrue(lane.deploy(tiny, to: .player))
        XCTAssertEqual(lane.currentBU(for: .player), 9)
        XCTAssertEqual(lane.remainingBU(for: .player), 1)
    }

    func testSecondApexIsRejectedOverCap() {
        let lane = Lane()
        let apexA = makeUnit(id: "apexA", sizeClass: .apex)
        let apexB = makeUnit(id: "apexB", sizeClass: .apex)

        XCTAssertTrue(lane.deploy(apexA, to: .player))
        // 8 + 8 = 16 > 10, must be rejected outright, not queued.
        XCTAssertFalse(lane.deploy(apexB, to: .player))
        XCTAssertEqual(lane.playerUnits.count, 1)
        XCTAssertEqual(lane.currentBU(for: .player), 8)
    }

    func testTinyHeadcountCapBindsBeforeBUCapDoes() {
        let lane = Lane()
        let tiny = makeUnit(id: "tiny", sizeClass: .tiny)

        for _ in 0..<6 {
            XCTAssertTrue(lane.deploy(tiny, to: .player))
        }
        XCTAssertEqual(lane.currentBU(for: .player), 6)

        // BU-wise there's room for a 7th tiny (6 + 1 = 7 <= 10), but GAME_DESIGN.md §4's
        // documented 6-unit Tiny swarm cap is what actually rejects it here — the headcount cap
        // and the BU cap are independent constraints, and this is the one that binds first.
        XCTAssertFalse(lane.deploy(tiny, to: .player))
        XCTAssertEqual(lane.currentBU(for: .player), 6)

        // A non-Tiny unit isn't subject to the headcount cap at all, only the BU cap: 6 + 3 = 9 <= 10 fits.
        let medium = makeUnit(id: "medium", sizeClass: .medium)
        XCTAssertTrue(lane.deploy(medium, to: .player))
        XCTAssertEqual(lane.currentBU(for: .player), 9)
    }

    func testBUCapRejectsNonTinyOverflowIndependentlyOfHeadcountCap() {
        let lane = Lane()
        for _ in 0..<5 {
            XCTAssertTrue(lane.deploy(makeUnit(id: "tiny", sizeClass: .tiny), to: .player))
        }
        XCTAssertEqual(lane.currentBU(for: .player), 5)

        // 5 Tiny units is under the 6-unit headcount cap, so what rejects the second Large below
        // is purely the BU cap: the first Large fits exactly (5 + 5 = 10 <= 10)...
        let large = makeUnit(id: "large", sizeClass: .large)
        XCTAssertTrue(lane.deploy(large, to: .player))
        XCTAssertEqual(lane.currentBU(for: .player), 10)

        // ...but a second Large has nowhere to go: 10 + 5 = 15 > 10.
        XCTAssertFalse(lane.deploy(large, to: .player))
    }

    func testDefeatedUnitsFreeUpBUForNewDeployments() {
        let lane = Lane()
        let apexA = makeUnit(id: "apexA", sizeClass: .apex)
        let apexB = makeUnit(id: "apexB", sizeClass: .apex)

        XCTAssertTrue(lane.deploy(apexA, to: .player))
        XCTAssertFalse(lane.deploy(apexB, to: .player))

        // Kill the first unit off, then the same deploy should succeed.
        XCTAssertEqual(lane.playerUnits.count, 1)
        lane.applyDamage(1_000_000, toUnitAt: 0, side: .player)
        lane.clearDefeatedUnits()
        XCTAssertEqual(lane.currentBU(for: .player), 0)

        XCTAssertTrue(lane.deploy(apexB, to: .player))
    }

    func testPlayerAndEnemySidesHaveIndependentCaps() {
        let lane = Lane()
        let apex = makeUnit(id: "apex", sizeClass: .apex)

        XCTAssertTrue(lane.deploy(apex, to: .player))
        // The enemy side's cap is unaffected by the player side's deployments.
        XCTAssertTrue(lane.deploy(apex, to: .enemy))
        XCTAssertEqual(lane.currentBU(for: .player), 8)
        XCTAssertEqual(lane.currentBU(for: .enemy), 8)
    }
}
