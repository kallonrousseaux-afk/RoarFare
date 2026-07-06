import Foundation

/// Which side of the lane a unit belongs to.
public enum Side: String, Sendable {
    case player
    case enemy
}

/// A live instance of a `UnitDefinition` on the lane — this is what `Lane` moves and fights with
/// in `Lane.tick(deltaTime:)`. Knockback is not modeled yet; see that method's doc comment.
public struct DeployedUnit: Identifiable, Sendable {
    public let id: UUID
    public let definition: UnitDefinition
    /// nil means the base (unevolved) form.
    public let activeBranchID: String?
    public var currentHP: Int
    public var position: Double
    /// Counts down to zero between attacks. Starts ready (0) so a unit doesn't sit idle on
    /// arrival before its first swing.
    public var attackCooldownRemaining: Double

    public init(definition: UnitDefinition, activeBranchID: String? = nil, position: Double) {
        self.id = UUID()
        self.definition = definition
        self.activeBranchID = activeBranchID
        self.position = position
        self.currentHP = Self.effectiveStats(definition: definition, activeBranchID: activeBranchID).maxHP
        self.attackCooldownRemaining = 0
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
