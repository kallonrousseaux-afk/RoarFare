import Foundation

/// Which side of the lane a unit belongs to.
public enum Side: String, Sendable {
    case player
    case enemy
}

/// A live instance of a `UnitDefinition` on the lane — this is what `Lane` tracks and what
/// battle simulation code (a future addition, see `GAME_DESIGN.md` §11) will move/fight with.
/// This pass only models deployment and effective stats; movement/attack/knockback ticking is
/// intentionally left for a later pass once this can be built and iterated on in Xcode.
public struct DeployedUnit: Identifiable, Sendable {
    public let id: UUID
    public let definition: UnitDefinition
    /// nil means the base (unevolved) form.
    public let activeBranchID: String?
    public var currentHP: Int
    public var position: Double

    public init(definition: UnitDefinition, activeBranchID: String? = nil, position: Double) {
        self.id = UUID()
        self.definition = definition
        self.activeBranchID = activeBranchID
        self.position = position
        self.currentHP = Self.effectiveStats(definition: definition, activeBranchID: activeBranchID).maxHP
    }

    public var blockingUnits: Int {
        definition.sizeClass.blockingUnits
    }

    public var isAlive: Bool {
        currentHP > 0
    }

    public var effectiveStats: UnitStats {
        Self.effectiveStats(definition: definition, activeBranchID: activeBranchID)
    }

    private static func effectiveStats(definition: UnitDefinition, activeBranchID: String?) -> UnitStats {
        guard let branchID = activeBranchID, let branch = definition.branch(withID: branchID) else {
            return definition.baseStats
        }
        return definition.baseStats.applying(branch.statModifiers)
    }
}
