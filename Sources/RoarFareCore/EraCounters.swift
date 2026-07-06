import Foundation

/// A first, deliberately partial slice of `GAME_DESIGN.md` §3's Era counter web: a flat damage
/// multiplier when one Era's attack lands on another.
///
/// Only the two cleanest, purely-numeric relationships from §3 are modeled here (Ice Age vs.
/// Triassic, Jurassic vs. Cretaceous). The rest of §3's web — Cretaceous ranged units kiting
/// Jurassic's slow attack speed, Triassic swarms surrounding a single Jurassic target, Sky
/// countering the not-yet-modeled Burrower enemy trait — describes *emergent* behavior that
/// already falls out of existing stats (range, attack speed, unit count via the BU system) or
/// depends on enemy traits that don't exist in the data model yet. Those aren't a flat multiplier
/// and modeling them properly (an actual trait/tag system on `UnitDefinition`) is separate,
/// larger work — not attempted here.
public enum EraCounters {
    public static func damageMultiplier(attacker: Era, defender: Era) -> Double {
        switch (attacker, defender) {
        case (.iceAge, .triassic): return 1.25
        case (.jurassic, .cretaceous): return 1.25
        default: return 1.0
        }
    }
}
