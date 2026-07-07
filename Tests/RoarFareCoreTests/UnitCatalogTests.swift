import XCTest
@testable import RoarFareCore

final class UnitCatalogTests: XCTestCase {
    func testBundledRosterDecodesAndCoversEverySizeClass() throws {
        let units = try UnitCatalog.loadAll()
        XCTAssertGreaterThanOrEqual(units.count, 20)

        let sizeClasses = Set(units.map(\.sizeClass))
        for sizeClass in SizeClass.allCases {
            XCTAssertTrue(sizeClasses.contains(sizeClass), "No unit found for \(sizeClass)")
        }
    }

    func testEveryUnitHasAtLeastOneEvolutionBranch() throws {
        let units = try UnitCatalog.loadAll()
        for unit in units {
            XCTAssertFalse(unit.evolutionBranches.isEmpty, "\(unit.id) has no evolution branches")
        }
    }

    func testLegendaryUnitsHaveTwoEvolutionBranches() throws {
        let units = try UnitCatalog.loadAll()
        let legendaries = units.filter { $0.rarity == .legendary }
        XCTAssertGreaterThanOrEqual(legendaries.count, 1)
        for unit in legendaries {
            XCTAssertEqual(unit.evolutionBranches.count, 2, "\(unit.id) is legendary but doesn't have 2 branches")
        }
    }

    func testDeinonychusHasBothBranchingExamplesFromDesignDoc() throws {
        let units = try UnitCatalog.loadAll()
        guard let deinonychus = units.first(where: { $0.id == "deinonychus" }) else {
            return XCTFail("deinonychus missing from bundled roster")
        }
        XCTAssertEqual(deinonychus.evolutionBranches.map(\.id).sorted(), ["ambush_striker", "pack_leader"])
    }

    func testEvolutionBranchModifiesEffectiveStatsButNotBaseDefinition() throws {
        let units = try UnitCatalog.loadAll()
        guard let parasaur = units.first(where: { $0.id == "parasaurolophus" }) else {
            return XCTFail("parasaurolophus missing from bundled roster")
        }

        let baseForm = DeployedUnit(definition: parasaur, position: 0)
        let rammer = DeployedUnit(definition: parasaur, activeBranchID: "skull_crest_rammer", position: 0)

        XCTAssertFalse(baseForm.effectiveStats.knockbackResistant)
        XCTAssertTrue(rammer.effectiveStats.knockbackResistant)
        XCTAssertGreaterThan(rammer.effectiveStats.maxHP, baseForm.effectiveStats.maxHP)

        // The underlying definition's base stats must stay untouched by the branch choice.
        XCTAssertEqual(parasaur.baseStats.maxHP, baseForm.effectiveStats.maxHP)

        // Skull-Crest Rammer is specifically the "charge attack with heavy knockback" branch
        // from GAME_DESIGN.md §5 — confirm the new dealsKnockback field decoded and applied.
        XCTAssertFalse(baseForm.effectiveStats.dealsKnockback)
        XCTAssertTrue(rammer.effectiveStats.dealsKnockback)
    }
}
