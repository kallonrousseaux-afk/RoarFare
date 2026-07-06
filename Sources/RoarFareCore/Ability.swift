import Foundation

/// Executable behavior for an `EvolutionBranch`, resolved inside `Lane.tick`. This is deliberately
/// small — just the two behaviors the current roster's branches actually need (Parasaurolophus's
/// Herd Caller aura, Deinonychus's Ambush Striker first-hit bonus) — not a general scripting
/// system. See `GAME_DESIGN.md` §5.
public enum Ability: Equatable, Sendable {
    /// While within `range` lane-position-units of an ally carrying this ability, that ally's
    /// effective `attackIntervalSeconds` is multiplied by `attackIntervalMultiplier` (a value
    /// below 1.0 speeds the ally's attacks up). Does not affect the aura-bearer's own side's
    /// enemies, and multiple overlapping auras don't stack — the strongest single multiplier wins.
    case attackSpeedAura(range: Double, attackIntervalMultiplier: Double)
    /// The first attack a unit lands after being deployed deals `damageMultiplier`x damage;
    /// every attack after that is normal. Tracked per-`DeployedUnit` via `hasUsedFirstStrike`.
    case firstHitBonus(damageMultiplier: Double)
}

/// Hand-written rather than relying on Swift's synthesized `Codable` for enums with associated
/// values — that synthesis exists, but its exact wire format isn't something to bet on without a
/// compiler available to confirm it. This format is simple and fully under our control instead:
/// `{"type": "attackSpeedAura", "range": 2.0, "attackIntervalMultiplier": 0.7}`
/// `{"type": "firstHitBonus", "damageMultiplier": 3.0}`
extension Ability: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case range
        case attackIntervalMultiplier
        case damageMultiplier
    }

    private enum Kind: String, Codable {
        case attackSpeedAura
        case firstHitBonus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .attackSpeedAura:
            let range = try container.decode(Double.self, forKey: .range)
            let multiplier = try container.decode(Double.self, forKey: .attackIntervalMultiplier)
            self = .attackSpeedAura(range: range, attackIntervalMultiplier: multiplier)
        case .firstHitBonus:
            let multiplier = try container.decode(Double.self, forKey: .damageMultiplier)
            self = .firstHitBonus(damageMultiplier: multiplier)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .attackSpeedAura(let range, let multiplier):
            try container.encode(Kind.attackSpeedAura, forKey: .type)
            try container.encode(range, forKey: .range)
            try container.encode(multiplier, forKey: .attackIntervalMultiplier)
        case .firstHitBonus(let multiplier):
            try container.encode(Kind.firstHitBonus, forKey: .type)
            try container.encode(multiplier, forKey: .damageMultiplier)
        }
    }
}
