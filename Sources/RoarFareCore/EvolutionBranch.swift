import Foundation

/// One of a unit's (usually two) divergent evolved forms. See `GAME_DESIGN.md` §5: unlike Battle Cats'
/// linear evolution, RoarFare branches change a unit's *role*, and both branches stay unlocked once
/// discovered — which branch is fielded is a per-deployed-copy choice, not a permanent upgrade path.
public struct EvolutionBranch: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let statModifiers: StatModifiers
    public let abilityDescription: String

    public init(id: String, name: String, statModifiers: StatModifiers, abilityDescription: String) {
        self.id = id
        self.name = name
        self.statModifiers = statModifiers
        self.abilityDescription = abilityDescription
    }
}
