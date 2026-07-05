import Foundation

/// Static, data-driven unit definition — see `GAME_DESIGN.md` §12: units are authored as data
/// (this struct, loaded from bundled JSON via `UnitCatalog`), not hardcoded per-unit subclasses.
public struct UnitDefinition: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let era: Era
    public let sizeClass: SizeClass
    public let rarity: Rarity
    public let deployCost: Int
    public let baseStats: UnitStats
    public let evolutionBranches: [EvolutionBranch]

    public init(
        id: String,
        name: String,
        era: Era,
        sizeClass: SizeClass,
        rarity: Rarity,
        deployCost: Int,
        baseStats: UnitStats,
        evolutionBranches: [EvolutionBranch] = []
    ) {
        self.id = id
        self.name = name
        self.era = era
        self.sizeClass = sizeClass
        self.rarity = rarity
        self.deployCost = deployCost
        self.baseStats = baseStats
        self.evolutionBranches = evolutionBranches
    }

    public func branch(withID branchID: String) -> EvolutionBranch? {
        evolutionBranches.first { $0.id == branchID }
    }
}

/// Loads the bundled unit roster. See `Resources/units.json` — the ~8 hand-authored MVP units
/// from `GAME_DESIGN.md` §11.
public enum UnitCatalog {
    public enum CatalogError: Error {
        case resourceNotFound
    }

    public static func loadAll() throws -> [UnitDefinition] {
        guard let url = Bundle.module.url(forResource: "units", withExtension: "json") else {
            throw CatalogError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([UnitDefinition].self, from: data)
    }
}
