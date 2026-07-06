import XCTest
@testable import RoarFareCore

final class CombatTickTests: XCTestCase {
    private func makeUnit(
        id: String,
        sizeClass: SizeClass = .medium,
        maxHP: Int = 100,
        attackDamage: Int = 10,
        attackIntervalSeconds: Double = 1.0,
        rangeUnits: Double = 1.0
    ) -> UnitDefinition {
        UnitDefinition(
            id: id,
            name: id,
            era: .cretaceous,
            sizeClass: sizeClass,
            rarity: .common,
            deployCost: 100,
            baseStats: UnitStats(
                maxHP: maxHP,
                attackDamage: attackDamage,
                attackIntervalSeconds: attackIntervalSeconds,
                rangeUnits: rangeUnits
            )
        )
    }

    func testUnitWalksTowardOpposingEndWhenUnobstructed() {
        let lane = Lane(length: 100)
        lane.deploy(makeUnit(id: "scout"), to: .player)

        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        XCTAssertEqual(lane.playerUnits[0].position, 5.0, accuracy: 0.0001)
    }

    func testFarApartUnitsWalkInsteadOfFightingOnFirstTick() {
        let lane = Lane(length: 100)
        lane.deploy(makeUnit(id: "attacker", attackDamage: 25, rangeUnits: 2.0), to: .player)
        lane.deploy(makeUnit(id: "target"), to: .enemy)

        // Distance starts at 100, well outside range 2.0 — both sides should just walk this tick.
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        XCTAssertEqual(lane.playerUnits[0].position, 5.0, accuracy: 0.0001)
        XCTAssertEqual(lane.enemyUnits[0].position, 95.0, accuracy: 0.0001)
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 100)
        XCTAssertEqual(lane.playerUnits[0].currentHP, 100)
    }

    func testOpposingUnitsFightOnceWithinRange() {
        let lane = Lane(length: 10)
        lane.deploy(makeUnit(id: "attacker", attackDamage: 30, attackIntervalSeconds: 1.0, rangeUnits: 1.0), to: .player)
        lane.deploy(makeUnit(id: "target", attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 1.0), to: .enemy)

        // Combined closing speed is 10 units/sec across a 10-unit lane, so 2 simulated seconds
        // (20 ticks of 0.1s) is generous room for them to meet and trade at least one hit each.
        for _ in 0..<20 {
            lane.tick(deltaTime: 0.1, walkSpeed: 5.0)
        }

        XCTAssertLessThan(lane.enemyUnits.first?.currentHP ?? 100, 100)
        XCTAssertLessThan(lane.playerUnits.first?.currentHP ?? 100, 100)
    }

    func testUnitDamagesOpposingBaseOnceItArrivesUnopposed() {
        let lane = Lane(length: 5, playerBaseHP: 1000, enemyBaseHP: 1000)
        lane.deploy(makeUnit(id: "attacker", attackDamage: 40, attackIntervalSeconds: 1.0, rangeUnits: 1.0), to: .player)

        // Tick 1: walk speed 5, lane length 5 — arrives exactly at the base this tick, but the
        // in-range/at-base check ran at the *start* of the tick (position was still 0), so no
        // attack fires yet.
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        XCTAssertEqual(lane.playerUnits[0].position, 5.0, accuracy: 0.0001)
        XCTAssertEqual(lane.enemyBaseHP, 1000)

        // Tick 2: now at the base at the start of the tick, so it attacks instead of moving.
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        XCTAssertEqual(lane.enemyBaseHP, 960)
    }

    func testDeadUnitsAreClearedAndFreeUpBUAfterATick() {
        let lane = Lane(length: 100)
        let apex = makeUnit(id: "apex", sizeClass: .apex, maxHP: 1)
        lane.deploy(apex, to: .player)
        lane.deploy(makeUnit(id: "enemyApex", sizeClass: .apex, attackDamage: 999, rangeUnits: 200), to: .enemy)

        XCTAssertEqual(lane.currentBU(for: .player), 8)

        // The enemy is in range immediately (rangeUnits: 200 covers the whole lane) and deals
        // lethal damage on the first tick, so the player's apex should be cleared afterward.
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        XCTAssertEqual(lane.playerUnits.count, 0)
        XCTAssertEqual(lane.currentBU(for: .player), 0)
    }
}
