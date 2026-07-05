import Foundation

public struct UnitStats: Codable, Equatable, Sendable {
    public var maxHP: Int
    public var attackDamage: Int
    public var attackIntervalSeconds: Double
    public var rangeUnits: Double
    public var knockbackResistant: Bool

    public init(
        maxHP: Int,
        attackDamage: Int,
        attackIntervalSeconds: Double,
        rangeUnits: Double,
        knockbackResistant: Bool = false
    ) {
        self.maxHP = maxHP
        self.attackDamage = attackDamage
        self.attackIntervalSeconds = attackIntervalSeconds
        self.rangeUnits = rangeUnits
        self.knockbackResistant = knockbackResistant
    }

    /// Applies an evolution branch's deltas (see `EvolutionBranch.statModifiers`) on top of these base stats.
    public func applying(_ modifiers: StatModifiers) -> UnitStats {
        UnitStats(
            maxHP: maxHP + modifiers.maxHP,
            attackDamage: attackDamage + modifiers.attackDamage,
            attackIntervalSeconds: attackIntervalSeconds + modifiers.attackIntervalSeconds,
            rangeUnits: rangeUnits,
            knockbackResistant: knockbackResistant || modifiers.grantsKnockbackResistance
        )
    }
}

/// Deltas an `EvolutionBranch` applies on top of a unit's `baseStats`. See `GAME_DESIGN.md` §5 —
/// branches change a unit's role, not just its numbers, but the numbers still need somewhere to live.
public struct StatModifiers: Codable, Equatable, Sendable {
    public var maxHP: Int
    public var attackDamage: Int
    public var attackIntervalSeconds: Double
    public var grantsKnockbackResistance: Bool

    public init(
        maxHP: Int = 0,
        attackDamage: Int = 0,
        attackIntervalSeconds: Double = 0,
        grantsKnockbackResistance: Bool = false
    ) {
        self.maxHP = maxHP
        self.attackDamage = attackDamage
        self.attackIntervalSeconds = attackIntervalSeconds
        self.grantsKnockbackResistance = grantsKnockbackResistance
    }
}
