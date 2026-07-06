import XCTest
@testable import RoarFareCore

final class CombatTickTests: XCTestCase {
    private func makeUnit(
        id: String,
        sizeClass: SizeClass = .medium,
        maxHP: Int = 100,
        attackDamage: Int = 10,
        attackIntervalSeconds: Double = 1.0,
        rangeUnits: Double = 1.0,
        knockbackResistant: Bool = false,
        dealsKnockback: Bool = false
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
                rangeUnits: rangeUnits,
                knockbackResistant: knockbackResistant,
                dealsKnockback: dealsKnockback
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

    func testKnockbackPushesNonResistantTargetBack() {
        let lane = Lane(length: 20)
        // rangeUnits: 0 so this unit never itself finds a target in range — it only ever walks
        // or (once knocked) sits at wherever it landed. Keeps the trace to just one moving part.
        lane.deploy(makeUnit(id: "enemy", maxHP: 1000, rangeUnits: 0), to: .enemy)

        // Let it advance into the lane for a tick before the attacker even exists, so it isn't
        // still sitting at the length-clamped spawn point when it gets hit (a hit there would
        // have nowhere further back to go, masking the knockback shift entirely).
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        XCTAssertEqual(lane.enemyUnits[0].position, 15.0, accuracy: 0.0001)

        lane.deploy(
            makeUnit(id: "rammer", attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 20, dealsKnockback: true),
            to: .player
        )
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        // Hit for 10 (-> 990 HP), knocked +3 (15 -> 18), then still takes its own -5/sec walk
        // this same tick (18 -> 13) — 3 further back than the 10 it would've reached unknocked.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 990)
        XCTAssertEqual(lane.enemyUnits[0].position, 13.0, accuracy: 0.0001)
    }

    func testKnockbackResistantTargetTakesDamageButIsNotShoved() {
        let lane = Lane(length: 20)
        lane.deploy(makeUnit(id: "tank", maxHP: 1000, rangeUnits: 0, knockbackResistant: true), to: .enemy)

        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        XCTAssertEqual(lane.enemyUnits[0].position, 15.0, accuracy: 0.0001)

        lane.deploy(
            makeUnit(id: "rammer", attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 20, dealsKnockback: true),
            to: .player
        )
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        // Still takes the hit, but knockbackResistant means no shove: 15 (unchanged by the hit)
        // minus its own -5/sec walk lands exactly on the un-knocked baseline of 10.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 990)
        XCTAssertEqual(lane.enemyUnits[0].position, 10.0, accuracy: 0.0001)
    }

    func testKnockbackDroppingUnitOutOfFrontlineRangeFreesItsBU() {
        let lane = Lane(length: 100)
        let large = makeUnit(id: "large", sizeClass: .large, rangeUnits: 0) // never engages on its own
        lane.deploy(large, to: .enemy) // enemyA, starts at position 100
        lane.deploy(large, to: .enemy) // enemyB, starts at position 100

        // Let both walk into the lane together for a tick before anything can hit them -- same
        // speed, no engagement, so they stay perfectly clustered and both still count toward BU.
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        XCTAssertEqual(lane.enemyUnits[0].position, 95.0, accuracy: 0.0001)
        XCTAssertEqual(lane.enemyUnits[1].position, 95.0, accuracy: 0.0001)
        XCTAssertEqual(lane.currentBU(for: .enemy), 10) // both Large (5 BU each), both still clustered

        lane.deploy(
            makeUnit(id: "rammer", attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 100, dealsKnockback: true),
            to: .player
        )
        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        // The rammer hits the tied-distance first enemy and knocks it back +3 (95 -> 98), then
        // that enemy still takes its own -5/sec walk this tick (98 -> 93); the untouched second
        // enemy just walks normally (95 -> 90). The knocked unit is now 3 lane-units behind the
        // front tip (90), which exceeds Lane.frontlineEngagementRange (2.0) -- it drops out of
        // the BU count even though it's still alive.
        XCTAssertEqual(lane.enemyUnits[0].position, 93.0, accuracy: 0.0001)
        XCTAssertEqual(lane.enemyUnits[1].position, 90.0, accuracy: 0.0001)
        XCTAssertEqual(lane.currentBU(for: .enemy), 5) // only the un-knocked unit still counts
    }
}
