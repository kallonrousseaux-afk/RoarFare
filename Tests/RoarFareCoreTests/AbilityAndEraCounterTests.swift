import XCTest
@testable import RoarFareCore

final class AbilityAndEraCounterTests: XCTestCase {
    private func makeUnit(
        id: String,
        era: Era = .cretaceous,
        sizeClass: SizeClass = .medium,
        maxHP: Int = 1000,
        attackDamage: Int = 10,
        attackIntervalSeconds: Double = 1.0,
        rangeUnits: Double = 1.0,
        branch: EvolutionBranch? = nil
    ) -> UnitDefinition {
        UnitDefinition(
            id: id,
            name: id,
            era: era,
            sizeClass: sizeClass,
            rarity: .common,
            deployCost: 100,
            baseStats: UnitStats(
                maxHP: maxHP,
                attackDamage: attackDamage,
                attackIntervalSeconds: attackIntervalSeconds,
                rangeUnits: rangeUnits
            ),
            evolutionBranches: branch.map { [$0] } ?? []
        )
    }

    // MARK: - Era counters

    func testEraCounterTableMatchesDesignDoc() {
        XCTAssertEqual(EraCounters.damageMultiplier(attacker: .iceAge, defender: .triassic), 1.25)
        XCTAssertEqual(EraCounters.damageMultiplier(attacker: .jurassic, defender: .cretaceous), 1.25)
        XCTAssertEqual(EraCounters.damageMultiplier(attacker: .cretaceous, defender: .jurassic), 1.0)
        XCTAssertEqual(EraCounters.damageMultiplier(attacker: .triassic, defender: .triassic), 1.0)
    }

    func testEraCounterMultiplierAppliesInCombat() {
        let lane = Lane(length: 10)
        lane.deploy(makeUnit(id: "iceAgeAttacker", era: .iceAge, attackDamage: 20, rangeUnits: 100), to: .player)
        lane.deploy(makeUnit(id: "triassicTarget", era: .triassic, attackDamage: 0, rangeUnits: 0), to: .enemy)

        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)

        // 20 * 1.25 (Ice Age vs. Triassic) = 25.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 975)
    }

    // MARK: - firstHitBonus

    func testFirstHitBonusAppliesOnceThenReverts() {
        let ambushBranch = EvolutionBranch(
            id: "ambush",
            name: "Ambush",
            statModifiers: StatModifiers(),
            abilityDescription: "test-only branch",
            ability: .firstHitBonus(damageMultiplier: 3.0)
        )
        let attacker = makeUnit(id: "striker", attackDamage: 10, rangeUnits: 100, branch: ambushBranch)
        let target = makeUnit(id: "target", attackDamage: 0, rangeUnits: 0)

        let lane = Lane(length: 10)
        lane.deploy(attacker, activeBranchID: "ambush", to: .player)
        lane.deploy(target, to: .enemy)

        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        // First hit: 10 * 3 = 30.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 970)

        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        // Second hit: back to normal, 10 more (not tripled again).
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 960)
    }

    func testFirstHitBonusDoesNotApplyWithoutTheBranchActive() {
        let ambushBranch = EvolutionBranch(
            id: "ambush",
            name: "Ambush",
            statModifiers: StatModifiers(),
            abilityDescription: "test-only branch",
            ability: .firstHitBonus(damageMultiplier: 3.0)
        )
        // Same unit, but deployed in its base form (no activeBranchID) -- the ability shouldn't fire.
        let attacker = makeUnit(id: "striker", attackDamage: 10, rangeUnits: 100, branch: ambushBranch)
        let target = makeUnit(id: "target", attackDamage: 0, rangeUnits: 0)

        let lane = Lane(length: 10)
        lane.deploy(attacker, to: .player) // no activeBranchID -- base form
        lane.deploy(target, to: .enemy)

        lane.tick(deltaTime: 1.0, walkSpeed: 5.0)
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 990) // plain 10 damage, no tripling
    }

    // MARK: - attackSpeedAura

    func testAttackSpeedAuraSpeedsUpNearbyAlly() {
        let callerBranch = EvolutionBranch(
            id: "caller",
            name: "Caller",
            statModifiers: StatModifiers(),
            abilityDescription: "test-only branch",
            ability: .attackSpeedAura(range: 10.0, attackIntervalMultiplier: 0.5)
        )
        let bearer = makeUnit(id: "bearer", attackDamage: 0, attackIntervalSeconds: 1.0, rangeUnits: 0, branch: callerBranch)
        let ally = makeUnit(id: "ally", attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 100)
        let target = makeUnit(id: "target", attackDamage: 0, rangeUnits: 0)

        let lane = Lane(length: 10)
        lane.deploy(bearer, activeBranchID: "caller", to: .player)
        lane.deploy(ally, to: .player)
        lane.deploy(target, to: .enemy)

        lane.tick(deltaTime: 0.5, walkSpeed: 5.0)
        // First hit fires immediately regardless of the aura (cooldown starts at 0): 1000 - 10 = 990.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 990)

        lane.tick(deltaTime: 0.5, walkSpeed: 5.0)
        // With the aura halving the ally's 1.0s interval to 0.5s, a second hit lands here at the
        // t=1.0s mark. Without the aura, the ally's cooldown after the first hit would've been the
        // full 1.0s and it wouldn't fire again until t=1.5s -- this second hit landing here is
        // exactly what the aura buys.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 980)
    }

    func testNoAuraWhenTheBearerIsInItsBaseForm() {
        let callerBranch = EvolutionBranch(
            id: "caller",
            name: "Caller",
            statModifiers: StatModifiers(),
            abilityDescription: "test-only branch",
            ability: .attackSpeedAura(range: 10.0, attackIntervalMultiplier: 0.5)
        )
        // Same unit and branch definition as the test above, but deployed without activeBranchID
        // -- i.e. its base (unevolved) form. DeployedUnit.activeAbility returns nil whenever
        // there's no active branch, regardless of what ability that branch would otherwise carry,
        // so the aura should have zero effect here even though the two units are right next to
        // each other the whole time.
        let bearer = makeUnit(id: "bearer", attackDamage: 0, attackIntervalSeconds: 1.0, rangeUnits: 0, branch: callerBranch)
        let ally = makeUnit(id: "ally", attackDamage: 10, attackIntervalSeconds: 1.0, rangeUnits: 100)
        let target = makeUnit(id: "target", attackDamage: 0, rangeUnits: 0)

        let lane = Lane(length: 10)
        lane.deploy(bearer, to: .player) // base form deployed -- no activeBranchID, so no ability active
        lane.deploy(ally, to: .player)
        lane.deploy(target, to: .enemy)

        lane.tick(deltaTime: 0.5, walkSpeed: 5.0)
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 990) // first hit fires regardless (cooldown starts at 0)

        lane.tick(deltaTime: 0.5, walkSpeed: 5.0)
        // No aura active -> ally's full 1.0s cooldown hasn't elapsed yet at t=1.0s, so no second hit.
        XCTAssertEqual(lane.enemyUnits[0].currentHP, 990)
    }
}
