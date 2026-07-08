import Foundation
import SpriteKit
import SwiftUI
import Combine
import UIKit

// MARK: - Core types (mirrors RoarFareCore, inlined so this is a single drop-in file)

enum Era: Hashable {
    case triassic, jurassic, cretaceous, iceAge, marine, sky

    var displayName: String {
        switch self {
        case .triassic: return "Triassic"
        case .jurassic: return "Jurassic"
        case .cretaceous: return "Cretaceous"
        case .iceAge: return "Ice Age"
        case .marine: return "Marine"
        case .sky: return "Sky"
        }
    }
}

enum SizeClass {
    case tiny, small, medium, large, apex

    var blockingUnits: Int {
        switch self {
        case .tiny: return 1
        case .small: return 2
        case .medium: return 3
        case .large: return 5
        case .apex: return 8
        }
    }

    /// Lane-crossing speed, scaled by size -- small/light dinosaurs cross the lane noticeably
    /// faster than lumbering Apex ones, instead of every unit sharing one uniform walk speed.
    /// Baseline is higher across the board than the old flat 5.0 (per "slightly faster").
    var baseWalkSpeed: Double {
        switch self {
        case .tiny: return 8.0
        case .small: return 7.0
        case .medium: return 6.0
        case .large: return 4.5
        case .apex: return 3.5
        }
    }
}

enum Rarity: Hashable {
    case common, rare, epic, legendary

    /// Gacha-style display names -- "SSR" for the top tier is the term the Summons screen uses,
    /// matching the genre convention instead of the internal `legendary` case name.
    var displayName: String {
        switch self {
        case .common: return "Common"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "SSR"
        }
    }
}

struct StatModifiers {
    var maxHP: Int = 0
    var attackDamage: Int = 0
    var attackIntervalSeconds: Double = 0
    var grantsKnockbackResistance: Bool = false
    var grantsKnockbackAttack: Bool = false
}

struct UnitStats {
    var maxHP: Int
    var attackDamage: Int
    var attackIntervalSeconds: Double
    var rangeUnits: Double
    var knockbackResistant: Bool = false
    var dealsKnockback: Bool = false
    // Species-level traits, not something an evolution branch changes -- a branch can make a
    // unit hit harder or tankier, but it doesn't turn a ground unit into a flyer. `isFlying`
    // units can only be attacked by units that are `isRanged` or `isFlying` themselves; a pure
    // melee ground unit skips flying targets entirely and just walks past them toward the base.
    var isRanged: Bool = false
    var isFlying: Bool = false

    func applying(_ modifiers: StatModifiers) -> UnitStats {
        UnitStats(
            maxHP: maxHP + modifiers.maxHP,
            attackDamage: attackDamage + modifiers.attackDamage,
            attackIntervalSeconds: attackIntervalSeconds + modifiers.attackIntervalSeconds,
            rangeUnits: rangeUnits,
            knockbackResistant: knockbackResistant || modifiers.grantsKnockbackResistance,
            dealsKnockback: dealsKnockback || modifiers.grantsKnockbackAttack,
            isRanged: isRanged,
            isFlying: isFlying
        )
    }
}

enum Ability {
    case attackSpeedAura(range: Double, attackIntervalMultiplier: Double)
    case firstHitBonus(damageMultiplier: Double)
}

struct EvolutionBranch {
    let id: String
    let name: String
    let statModifiers: StatModifiers
    let abilityDescription: String
    let ability: Ability?

    init(id: String, name: String, statModifiers: StatModifiers, abilityDescription: String, ability: Ability? = nil) {
        self.id = id
        self.name = name
        self.statModifiers = statModifiers
        self.abilityDescription = abilityDescription
        self.ability = ability
    }
}

/// A themed group of units that buffs its own members when 2+ of them are alive on the same
/// side at once -- e.g. Velociraptor's "Pack Hunter" branch flavor text ("Sharper coordinated
/// strikes") was previously just text; this makes it a real, live combat bonus.
enum SynergyGroup: Equatable {
    case raptorPack
    case armoredLine
    case apexTitans

    /// Minimum alive members (including the unit itself) needed to activate the bonus.
    var requiredCount: Int { 2 }

    var displayName: String {
        switch self {
        case .raptorPack: return "Raptor Pack"
        case .armoredLine: return "Armored Line"
        case .apexTitans: return "Apex Titans"
        }
    }

    /// Multiplies attackDamage while active. 1.0 means this group doesn't buff damage.
    var attackDamageMultiplier: Double {
        switch self {
        case .raptorPack: return 1.25
        case .apexTitans: return 1.20
        case .armoredLine: return 1.0
        }
    }

    /// Multiplies attackIntervalSeconds while active (below 1.0 = attacks faster).
    var attackIntervalMultiplier: Double {
        switch self {
        case .armoredLine: return 0.85
        default: return 1.0
        }
    }
}

struct UnitDefinition: Identifiable {
    let id: String
    let name: String
    let era: Era
    let sizeClass: SizeClass
    let rarity: Rarity
    let deployCost: Int
    let baseStats: UnitStats
    let evolutionBranches: [EvolutionBranch]
    let synergyGroup: SynergyGroup?

    init(
        id: String, name: String, era: Era, sizeClass: SizeClass, rarity: Rarity,
        deployCost: Int, baseStats: UnitStats, evolutionBranches: [EvolutionBranch] = [],
        synergyGroup: SynergyGroup? = nil
    ) {
        self.id = id
        self.name = name
        self.era = era
        self.sizeClass = sizeClass
        self.rarity = rarity
        self.deployCost = deployCost
        self.baseStats = baseStats
        self.evolutionBranches = evolutionBranches
        self.synergyGroup = synergyGroup
    }

    func branch(withID branchID: String) -> EvolutionBranch? {
        evolutionBranches.first { $0.id == branchID }
    }
}

enum Side {
    case player, enemy
}

struct DeployedUnit: Identifiable {
    let id = UUID()
    let definition: UnitDefinition
    let activeBranchID: String?
    /// From `PlayerProfile.level(for:)` at deploy time -- Enhance and evolution-branch stack
    /// independently (see `effectiveStats`), so a unit can be both evolved and leveled up.
    let enhancementLevel: Int
    var currentHP: Int
    var position: Double
    var attackCooldownRemaining: Double = 0
    var hasUsedFirstStrike: Bool = false

    init(definition: UnitDefinition, activeBranchID: String? = nil, enhancementLevel: Int = 1, position: Double) {
        self.definition = definition
        self.activeBranchID = activeBranchID
        self.enhancementLevel = enhancementLevel
        self.position = position
        self.currentHP = Self.effectiveStats(definition: definition, activeBranchID: activeBranchID, enhancementLevel: enhancementLevel).maxHP
    }

    var blockingUnits: Int { definition.sizeClass.blockingUnits }
    var isAlive: Bool { currentHP > 0 }
    var effectiveStats: UnitStats {
        Self.effectiveStats(definition: definition, activeBranchID: activeBranchID, enhancementLevel: enhancementLevel)
    }

    var activeAbility: Ability? {
        guard let branchID = activeBranchID else { return nil }
        return definition.branch(withID: branchID)?.ability
    }

    /// +5% attackDamage and maxHP per Enhance level above 1 (level `PlayerProfile.maxLevel` =
    /// +45%), applied on top of the evolution branch's stat deltas.
    private static func effectiveStats(definition: UnitDefinition, activeBranchID: String?, enhancementLevel: Int) -> UnitStats {
        let branched: UnitStats
        if let branchID = activeBranchID, let branch = definition.branch(withID: branchID) {
            branched = definition.baseStats.applying(branch.statModifiers)
        } else {
            branched = definition.baseStats
        }
        guard enhancementLevel > 1 else { return branched }
        let multiplier = 1.0 + 0.05 * Double(enhancementLevel - 1)
        var enhanced = branched
        enhanced.maxHP = Int((Double(branched.maxHP) * multiplier).rounded())
        enhanced.attackDamage = Int((Double(branched.attackDamage) * multiplier).rounded())
        return enhanced
    }
}

enum EraCounters {
    static func damageMultiplier(attacker: Era, defender: Era) -> Double {
        switch (attacker, defender) {
        case (.iceAge, .triassic): return 1.25
        case (.jurassic, .cretaceous): return 1.25
        default: return 1.0
        }
    }
}

final class Lane {
    static let defaultFrontlineBUCap = 10
    static let tinyUnitHeadcountCap = 6
    static let knockbackDistance = 3.0
    static let frontlineEngagementRange = 2.0

    // A `var`, not a fixed constant -- `BattleScene` raises this during the double-Amber final
    // stretch (see `isInDoubleAmberPhase`) so bigger frontlines are possible in the climax, not
    // just faster income.
    var frontlineBUCap = Lane.defaultFrontlineBUCap

    let length: Double
    private(set) var playerUnits: [DeployedUnit] = []
    private(set) var enemyUnits: [DeployedUnit] = []
    private(set) var playerBaseHP: Int
    private(set) var enemyBaseHP: Int

    init(length: Double = 100, playerBaseHP: Int = 1000, enemyBaseHP: Int = 1000) {
        self.length = length
        self.playerBaseHP = playerBaseHP
        self.enemyBaseHP = enemyBaseHP
    }

    func currentBU(for side: Side) -> Int {
        frontlineUnits(for: side).reduce(0) { $0 + $1.blockingUnits }
    }

    func remainingBU(for side: Side) -> Int {
        max(0, frontlineBUCap - currentBU(for: side))
    }

    private func tinyUnitCount(for side: Side) -> Int {
        frontlineUnits(for: side).filter { $0.definition.sizeClass == .tiny }.count
    }

    private func frontlineUnits(for side: Side) -> [DeployedUnit] {
        let alive = units(for: side).filter { $0.isAlive }
        guard let tip = frontTipPosition(for: side, aliveUnits: alive) else { return [] }
        return alive.filter { abs($0.position - tip) <= Self.frontlineEngagementRange }
    }

    private func frontTipPosition(for side: Side, aliveUnits: [DeployedUnit]) -> Double? {
        switch side {
        case .player: return aliveUnits.map(\.position).max()
        case .enemy: return aliveUnits.map(\.position).min()
        }
    }

    @discardableResult
    func deploy(_ definition: UnitDefinition, activeBranchID: String? = nil, enhancementLevel: Int = 1, to side: Side) -> Bool {
        guard currentBU(for: side) + definition.sizeClass.blockingUnits <= frontlineBUCap else {
            return false
        }
        if definition.sizeClass == .tiny, tinyUnitCount(for: side) >= Self.tinyUnitHeadcountCap {
            return false
        }
        let startPosition = side == .player ? 0 : length
        let unit = DeployedUnit(definition: definition, activeBranchID: activeBranchID, enhancementLevel: enhancementLevel, position: startPosition)
        switch side {
        case .player: playerUnits.append(unit)
        case .enemy: enemyUnits.append(unit)
        }
        return true
    }

    func clearDefeatedUnits() {
        playerUnits.removeAll { !$0.isAlive }
        enemyUnits.removeAll { !$0.isAlive }
    }

    /// Direct base-HP damage, bypassing units/lane position entirely -- backs the one-shot
    /// manual base attack (`BattleScene.fireBaseAttack`), Battle Cats' Cat Cannon equivalent.
    func dealDamageToBase(_ amount: Int, of side: Side) {
        switch side {
        case .player: playerBaseHP -= amount
        case .enemy: enemyBaseHP -= amount
        }
    }

    func tick(deltaTime: Double) {
        resolveCombatAndMovement(
            attackers: &playerUnits, defenders: &enemyUnits,
            advancesTowardIncreasingPosition: true, defendersBaseHP: &enemyBaseHP,
            deltaTime: deltaTime
        )
        resolveCombatAndMovement(
            attackers: &enemyUnits, defenders: &playerUnits,
            advancesTowardIncreasingPosition: false, defendersBaseHP: &playerBaseHP,
            deltaTime: deltaTime
        )
        clearDefeatedUnits()
    }

    /// Flying units get a flat speed bonus on top of their size-class baseline -- they're
    /// agile fliers, not just "a ground unit that happens to dodge melee" (see `SizeClass`
    /// for the size scaling itself).
    private static let flyingWalkSpeedBonus = 1.5

    private func resolveCombatAndMovement(
        attackers: inout [DeployedUnit], defenders: inout [DeployedUnit],
        advancesTowardIncreasingPosition: Bool, defendersBaseHP: inout Int,
        deltaTime: Double
    ) {
        for i in attackers.indices {
            guard attackers[i].isAlive else { continue }
            var stats = attackers[i].effectiveStats
            stats.attackIntervalSeconds *= Self.auraAttackIntervalMultiplier(for: attackers[i], allies: attackers)
            if let group = attackers[i].definition.synergyGroup,
               Self.synergyIsActive(group, allies: attackers) {
                stats.attackDamage = Int((Double(stats.attackDamage) * group.attackDamageMultiplier).rounded())
                stats.attackIntervalSeconds *= group.attackIntervalMultiplier
            }

            if attackers[i].attackCooldownRemaining > 0 {
                attackers[i].attackCooldownRemaining -= deltaTime
            }

            let canTargetFlying = stats.isRanged || stats.isFlying
            if let targetIndex = Self.nearestAliveDefenderInRange(
                from: attackers[i].position, range: stats.rangeUnits, defenders: defenders,
                canTargetFlying: canTargetFlying
            ) {
                if attackers[i].attackCooldownRemaining <= 0 {
                    let eraAdjusted = Self.eraAdjustedDamage(
                        attackerEra: attackers[i].definition.era,
                        defenderEra: defenders[targetIndex].definition.era,
                        baseDamage: stats.attackDamage
                    )
                    let finalDamage = Self.applyFirstHitBonus(to: &attackers[i], baseDamage: eraAdjusted)
                    defenders[targetIndex].currentHP -= finalDamage
                    attackers[i].attackCooldownRemaining = stats.attackIntervalSeconds

                    if stats.dealsKnockback, defenders[targetIndex].isAlive,
                       !defenders[targetIndex].effectiveStats.knockbackResistant {
                        let shift = Self.knockbackDistance * (advancesTowardIncreasingPosition ? 1.0 : -1.0)
                        var newPosition = defenders[targetIndex].position + shift
                        newPosition = advancesTowardIncreasingPosition ? min(newPosition, length) : max(newPosition, 0)
                        defenders[targetIndex].position = newPosition
                    }
                }
            } else if isAtOpposingBase(attackers[i], advancesTowardIncreasingPosition: advancesTowardIncreasingPosition) {
                if attackers[i].attackCooldownRemaining <= 0 {
                    let finalDamage = Self.applyFirstHitBonus(to: &attackers[i], baseDamage: stats.attackDamage)
                    defendersBaseHP -= finalDamage
                    attackers[i].attackCooldownRemaining = stats.attackIntervalSeconds
                }
            } else {
                var unitWalkSpeed = attackers[i].definition.sizeClass.baseWalkSpeed
                if stats.isFlying { unitWalkSpeed += Self.flyingWalkSpeedBonus }
                let delta = (advancesTowardIncreasingPosition ? 1.0 : -1.0) * unitWalkSpeed * deltaTime
                var newPosition = attackers[i].position + delta
                newPosition = advancesTowardIncreasingPosition ? min(newPosition, length) : max(newPosition, 0)
                attackers[i].position = newPosition
            }
        }
    }

    private func isAtOpposingBase(_ unit: DeployedUnit, advancesTowardIncreasingPosition: Bool) -> Bool {
        advancesTowardIncreasingPosition ? unit.position >= length : unit.position <= 0
    }

    private static func applyFirstHitBonus(to attacker: inout DeployedUnit, baseDamage: Int) -> Int {
        guard case .firstHitBonus(let multiplier)? = attacker.activeAbility, !attacker.hasUsedFirstStrike else {
            return baseDamage
        }
        attacker.hasUsedFirstStrike = true
        return Int((Double(baseDamage) * multiplier).rounded())
    }

    private static func eraAdjustedDamage(attackerEra: Era, defenderEra: Era, baseDamage: Int) -> Int {
        Int((Double(baseDamage) * EraCounters.damageMultiplier(attacker: attackerEra, defender: defenderEra)).rounded())
    }

    private static func auraAttackIntervalMultiplier(for unit: DeployedUnit, allies: [DeployedUnit]) -> Double {
        var best = 1.0
        for ally in allies {
            guard ally.id != unit.id, ally.isAlive else { continue }
            guard case .attackSpeedAura(let range, let multiplier)? = ally.activeAbility else { continue }
            guard abs(ally.position - unit.position) <= range else { continue }
            best = min(best, multiplier)
        }
        return best
    }

    /// True once `group.requiredCount` alive members of the same synergy group (the unit
    /// itself included) are on this side, no matter where they are on the lane -- unlike the
    /// attack-speed aura, synergy isn't position/range-gated, it's about squad composition.
    private static func synergyIsActive(_ group: SynergyGroup, allies: [DeployedUnit]) -> Bool {
        let memberCount = allies.filter { $0.isAlive && $0.definition.synergyGroup == group }.count
        return memberCount >= group.requiredCount
    }

    private static func nearestAliveDefenderInRange(
        from position: Double, range: Double, defenders: [DeployedUnit], canTargetFlying: Bool
    ) -> Int? {
        var bestIndex: Int?
        var bestDistance = Double.infinity
        for (index, defender) in defenders.enumerated() {
            guard defender.isAlive else { continue }
            // Pure melee ground units (not ranged, not flying) can't select a flying target at
            // all -- they just keep walking, same as if nothing were there. Only ranged or
            // flying attackers can actually hit a flying defender.
            if defender.effectiveStats.isFlying, !canTargetFlying { continue }
            let distance = abs(defender.position - position)
            guard distance <= range else { continue }
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func units(for side: Side) -> [DeployedUnit] {
        side == .player ? playerUnits : enemyUnits
    }
}

// MARK: - Bundled roster (hardcoded here instead of loaded from JSON)

let bundledUnits: [UnitDefinition] = [
    UnitDefinition(
        id: "compsognathus", name: "Compsognathus", era: .triassic, sizeClass: .tiny, rarity: .common,
        deployCost: 60, baseStats: UnitStats(maxHP: 40, attackDamage: 8, attackIntervalSeconds: 0.6, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "swift_scavenger", name: "Swift Scavenger", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Faster attacks.")
        ]
    ),
    UnitDefinition(
        id: "velociraptor", name: "Velociraptor", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 300, baseStats: UnitStats(maxHP: 120, attackDamage: 30, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "pack_hunter", name: "Pack Hunter", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "Sharper coordinated strikes, more damage.")
        ],
        synergyGroup: .raptorPack
    ),
    UnitDefinition(
        id: "deinonychus", name: "Deinonychus", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 320, baseStats: UnitStats(maxHP: 130, attackDamage: 32, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "pack_leader", name: "Pack Leader", statModifiers: StatModifiers(), abilityDescription: "Pack Hunting bonus with other raptors."),
            EvolutionBranch(id: "ambush_striker", name: "Ambush Striker", statModifiers: StatModifiers(maxHP: -10), abilityDescription: "First hit deals 3x damage.", ability: .firstHitBonus(damageMultiplier: 3.0))
        ],
        synergyGroup: .raptorPack
    ),
    UnitDefinition(
        id: "parasaurolophus", name: "Parasaurolophus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 450, baseStats: UnitStats(maxHP: 320, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "herd_caller", name: "Herd Caller", statModifiers: StatModifiers(attackDamage: -24), abilityDescription: "Attack-speed aura.", ability: .attackSpeedAura(range: 10.0, attackIntervalMultiplier: 0.7)),
            EvolutionBranch(id: "skull_crest_rammer", name: "Skull-Crest Rammer", statModifiers: StatModifiers(maxHP: 60, attackDamage: 10, grantsKnockbackResistance: true, grantsKnockbackAttack: true), abilityDescription: "Knockback charge attack.")
        ]
    ),
    UnitDefinition(
        id: "triceratops", name: "Triceratops", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 420, attackDamage: 34, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "bulwark_horn", name: "Bulwark Horn", statModifiers: StatModifiers(maxHP: 80, grantsKnockbackAttack: true), abilityDescription: "Horn charge knocks enemies back.")
        ],
        synergyGroup: .armoredLine
    ),
    UnitDefinition(
        id: "stegosaurus", name: "Stegosaurus", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 750, baseStats: UnitStats(maxHP: 700, attackDamage: 55, attackIntervalSeconds: 1.6, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "thagomizer_guardian", name: "Thagomizer Guardian", statModifiers: StatModifiers(attackDamage: 15, grantsKnockbackAttack: true), abilityDescription: "Tail-spike swing knocks enemies back.")
        ],
        synergyGroup: .armoredLine
    ),
    UnitDefinition(
        id: "ankylosaurus", name: "Ankylosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 800, baseStats: UnitStats(maxHP: 780, attackDamage: 48, attackIntervalSeconds: 1.4, rangeUnits: 1.2, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "club_tail_breaker", name: "Club-Tail Breaker", statModifiers: StatModifiers(attackDamage: 20, grantsKnockbackAttack: true), abilityDescription: "Heavier tail-club hits knock enemies back.")
        ],
        synergyGroup: .armoredLine
    ),
    UnitDefinition(
        id: "tyrannosaurus_rex", name: "Tyrannosaurus Rex", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1800, baseStats: UnitStats(maxHP: 1600, attackDamage: 220, attackIntervalSeconds: 2.2, rangeUnits: 1.0, knockbackResistant: true),
        // SSR-tier: two evolutions, per the current art/roster pass.
        evolutionBranches: [
            EvolutionBranch(id: "tyrant_king", name: "Tyrant King", statModifiers: StatModifiers(maxHP: 200, attackDamage: 40), abilityDescription: "Pure apex-predator scaling: more HP, more damage."),
            EvolutionBranch(id: "bone_crusher", name: "Bone-Crusher", statModifiers: StatModifiers(attackDamage: 80, attackIntervalSeconds: 0.3, grantsKnockbackAttack: true), abilityDescription: "Slower but devastating bite that knocks enemies back.")
        ],
        synergyGroup: .apexTitans
    ),
    // MARK: Roster expansion -- fills out era/size coverage and builds three units the design
    // doc already named (Pack Hunting §6's raptor pack and ceratopsian wall) but never actually
    // implemented: Utahraptor, Styracosaurus, Pentaceratops.
    UnitDefinition(
        id: "coelophysis", name: "Coelophysis", era: .triassic, sizeClass: .tiny, rarity: .common,
        deployCost: 55, baseStats: UnitStats(maxHP: 35, attackDamage: 7, attackIntervalSeconds: 0.55, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "swarm_runner", name: "Swarm Runner", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Faster attacks.")
        ]
    ),
    UnitDefinition(
        id: "plateosaurus", name: "Plateosaurus", era: .triassic, sizeClass: .large, rarity: .rare,
        deployCost: 780, baseStats: UnitStats(maxHP: 720, attackDamage: 50, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "titan_browser", name: "Titan Browser", statModifiers: StatModifiers(maxHP: 100), abilityDescription: "Bulkier frontline tank.")
        ]
    ),
    UnitDefinition(
        id: "dilophosaurus", name: "Dilophosaurus", era: .jurassic, sizeClass: .small, rarity: .rare,
        // Retrofitted as this roster's first long-ranged unit -- venom-spitting fits a ranged
        // attacker thematically, and rangeUnits 3.0 is well past melee's ~1.0-1.2 norm.
        deployCost: 310, baseStats: UnitStats(maxHP: 125, attackDamage: 34, attackIntervalSeconds: 0.9, rangeUnits: 3.0, isRanged: true),
        evolutionBranches: [
            EvolutionBranch(id: "venom_spitter", name: "Venom Spitter", statModifiers: StatModifiers(attackDamage: 10), abilityDescription: "Venomous bite deals extra damage.")
        ]
    ),
    UnitDefinition(
        id: "allosaurus", name: "Allosaurus", era: .jurassic, sizeClass: .large, rarity: .epic,
        deployCost: 820, baseStats: UnitStats(maxHP: 750, attackDamage: 60, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "apex_stalker", name: "Apex Stalker", statModifiers: StatModifiers(attackDamage: 25), abilityDescription: "Sharper hunting instincts, more damage.")
        ]
    ),
    UnitDefinition(
        id: "brachiosaurus", name: "Brachiosaurus", era: .jurassic, sizeClass: .apex, rarity: .legendary,
        deployCost: 1700, baseStats: UnitStats(maxHP: 2000, attackDamage: 150, attackIntervalSeconds: 2.5, rangeUnits: 1.0, knockbackResistant: true),
        // SSR-tier: two evolutions.
        evolutionBranches: [
            EvolutionBranch(id: "sky_reacher", name: "Sky Reacher", statModifiers: StatModifiers(maxHP: 400), abilityDescription: "Even more HP -- a true walking fortress."),
            EvolutionBranch(id: "canopy_titan", name: "Canopy Titan", statModifiers: StatModifiers(attackDamage: -50), abilityDescription: "Loses personal damage; grants an attack-speed aura to nearby allies.", ability: .attackSpeedAura(range: 12.0, attackIntervalMultiplier: 0.8))
        ],
        synergyGroup: .apexTitans
    ),
    UnitDefinition(
        id: "utahraptor", name: "Utahraptor", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 330, baseStats: UnitStats(maxHP: 140, attackDamage: 34, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "slash_hunter", name: "Slash Hunter", statModifiers: StatModifiers(attackDamage: 12), abilityDescription: "Bigger sickle-claw damage.")
        ],
        synergyGroup: .raptorPack
    ),
    UnitDefinition(
        id: "styracosaurus", name: "Styracosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 520, baseStats: UnitStats(maxHP: 440, attackDamage: 36, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "spike_crown", name: "Spike Crown", statModifiers: StatModifiers(maxHP: 60, grantsKnockbackResistance: true), abilityDescription: "Reinforced frill, even harder to knock back.")
        ],
        synergyGroup: .armoredLine
    ),
    UnitDefinition(
        id: "pentaceratops", name: "Pentaceratops", era: .cretaceous, sizeClass: .medium, rarity: .epic,
        deployCost: 600, baseStats: UnitStats(maxHP: 500, attackDamage: 38, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "five_horn_vanguard", name: "Five-Horn Vanguard", statModifiers: StatModifiers(maxHP: 80, attackDamage: 10), abilityDescription: "All five horns reinforced -- tougher and stronger.")
        ],
        synergyGroup: .armoredLine
    ),
    UnitDefinition(
        id: "pachycephalosaurus", name: "Pachycephalosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 480, baseStats: UnitStats(maxHP: 350, attackDamage: 26, attackIntervalSeconds: 1.1, rangeUnits: 1.0, dealsKnockback: true),
        evolutionBranches: [
            EvolutionBranch(id: "dome_rammer", name: "Dome Rammer", statModifiers: StatModifiers(attackDamage: 14, grantsKnockbackAttack: true), abilityDescription: "Harder headbutt, still knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "spinosaurus", name: "Spinosaurus", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1900, baseStats: UnitStats(maxHP: 1500, attackDamage: 240, attackIntervalSeconds: 2.0, rangeUnits: 1.2, knockbackResistant: true),
        // SSR-tier: two evolutions.
        evolutionBranches: [
            EvolutionBranch(id: "river_tyrant", name: "River Tyrant", statModifiers: StatModifiers(maxHP: 300, attackDamage: 40), abilityDescription: "Pure apex scaling: more HP, more damage."),
            EvolutionBranch(id: "sail_predator", name: "Sail Predator", statModifiers: StatModifiers(maxHP: -50), abilityDescription: "First attack after deployment deals bonus damage.", ability: .firstHitBonus(damageMultiplier: 2.5))
        ],
        synergyGroup: .apexTitans
    ),
    UnitDefinition(
        id: "iguanodon", name: "Iguanodon", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 470, baseStats: UnitStats(maxHP: 340, attackDamage: 22, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "thumb_spike_defender", name: "Thumb-Spike Defender", statModifiers: StatModifiers(maxHP: 50, grantsKnockbackResistance: true), abilityDescription: "Braces with its thumb spike, harder to knock back.")
        ]
    ),
    UnitDefinition(
        id: "ceratosaurus", name: "Ceratosaurus", era: .jurassic, sizeClass: .medium, rarity: .rare,
        deployCost: 530, baseStats: UnitStats(maxHP: 380, attackDamage: 38, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "horn_snout_hunter", name: "Horn-Snout Hunter", statModifiers: StatModifiers(attackDamage: 14), abilityDescription: "More aggressive hunting stance, more damage.")
        ]
    ),
    // This roster's first flying unit -- no character art yet (renders as an elevated circle,
    // see `sync`'s altitudeOffset), added specifically to make the new melee-can't-hit-flying
    // targeting rule actually testable. Only ranged or flying attackers can hit it.
    UnitDefinition(
        id: "pteranodon", name: "Pteranodon", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 340, baseStats: UnitStats(maxHP: 100, attackDamage: 26, attackIntervalSeconds: 0.9, rangeUnits: 1.0, isFlying: true),
        evolutionBranches: [
            EvolutionBranch(id: "sky_diver", name: "Sky Diver", statModifiers: StatModifiers(attackDamage: 10), abilityDescription: "Dives from above for a harder strike.")
        ]
    ),
    // MARK: Second roster expansion -- 80 more units to bring the character-art roster's
    // "100 characters" concept fully into the playable data model. These render with the same
    // procedural chibi-circle visuals as every other unit (see BattleScene.makeVisual), so
    // there's no longer an art-completeness gate on which designed units are playable.
    UnitDefinition(
        id: "microraptor", name: "Microraptor", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 60, baseStats: UnitStats(maxHP: 38, attackDamage: 8, attackIntervalSeconds: 0.55, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "four_wing_glider", name: "Four-Wing Glider", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Glides between strikes for faster attacks.")
        ]
    ),
    UnitDefinition(
        id: "caudipteryx", name: "Caudipteryx", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 55, baseStats: UnitStats(maxHP: 32, attackDamage: 6, attackIntervalSeconds: 0.6, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "plume_dancer", name: "Plume Dancer", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Quick darting strikes.")
        ]
    ),
    UnitDefinition(
        id: "archaeopteryx", name: "Archaeopteryx", era: .jurassic, sizeClass: .tiny, rarity: .common,
        deployCost: 65, baseStats: UnitStats(maxHP: 34, attackDamage: 7, attackIntervalSeconds: 0.55, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "sky_glider", name: "Sky Glider", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Light frame darts between attacks.")
        ]
    ),
    UnitDefinition(
        id: "eoraptor", name: "Eoraptor", era: .triassic, sizeClass: .tiny, rarity: .common,
        deployCost: 50, baseStats: UnitStats(maxHP: 30, attackDamage: 6, attackIntervalSeconds: 0.55, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "first_hunter", name: "First Hunter", statModifiers: StatModifiers(attackDamage: 4), abilityDescription: "One of the earliest hunters, sharper bite.")
        ]
    ),
    UnitDefinition(
        id: "hypsilophodon", name: "Hypsilophodon", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 55, baseStats: UnitStats(maxHP: 36, attackDamage: 5, attackIntervalSeconds: 0.6, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "quick_grazer", name: "Quick Grazer", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Fast nimble strikes.")
        ]
    ),
    UnitDefinition(
        id: "leaellynasaura", name: "Leaellynasaura", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 55, baseStats: UnitStats(maxHP: 40, attackDamage: 5, attackIntervalSeconds: 0.6, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "polar_sprinter", name: "Polar Sprinter", statModifiers: StatModifiers(maxHP: 10), abilityDescription: "Built for cold endurance, tougher.")
        ]
    ),
    UnitDefinition(
        id: "psittacosaurus", name: "Psittacosaurus", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 60, baseStats: UnitStats(maxHP: 42, attackDamage: 6, attackIntervalSeconds: 0.6, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "quill_tail", name: "Quill-Tail", statModifiers: StatModifiers(grantsKnockbackResistance: true), abilityDescription: "Bristled tail braces against hits.")
        ]
    ),
    UnitDefinition(
        id: "scutellosaurus", name: "Scutellosaurus", era: .jurassic, sizeClass: .tiny, rarity: .common,
        deployCost: 60, baseStats: UnitStats(maxHP: 44, attackDamage: 5, attackIntervalSeconds: 0.6, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "scale_guard", name: "Scale Guard", statModifiers: StatModifiers(maxHP: 15), abilityDescription: "Extra scutes add toughness.")
        ]
    ),
    UnitDefinition(
        id: "dilong", name: "Dilong", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 65, baseStats: UnitStats(maxHP: 40, attackDamage: 8, attackIntervalSeconds: 0.55, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "downy_stalker", name: "Downy Stalker", statModifiers: StatModifiers(attackDamage: 4), abilityDescription: "Feathered ambusher, sharper bite.")
        ]
    ),
    UnitDefinition(
        id: "thescelosaurus", name: "Thescelosaurus", era: .cretaceous, sizeClass: .tiny, rarity: .common,
        deployCost: 58, baseStats: UnitStats(maxHP: 40, attackDamage: 6, attackIntervalSeconds: 0.6, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "steady_heart", name: "Steady Heart", statModifiers: StatModifiers(maxHP: 12), abilityDescription: "Tougher stamina, more HP.")
        ]
    ),
    UnitDefinition(
        id: "oviraptor", name: "Oviraptor", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 310, baseStats: UnitStats(maxHP: 122, attackDamage: 28, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "egg_guardian", name: "Egg Guardian", statModifiers: StatModifiers(maxHP: 20), abilityDescription: "Protective instincts, more HP.")
        ]
    ),
    UnitDefinition(
        id: "protoceratops", name: "Protoceratops", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 300, baseStats: UnitStats(maxHP: 132, attackDamage: 24, attackIntervalSeconds: 0.9, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "nest_defender", name: "Nest Defender", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Headbutts intruders back.")
        ]
    ),
    UnitDefinition(
        id: "beipiaosaurus", name: "Beipiaosaurus", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 300, baseStats: UnitStats(maxHP: 116, attackDamage: 22, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "bristle_coat", name: "Bristle Coat", statModifiers: StatModifiers(maxHP: 15), abilityDescription: "Shaggy feathers add padding.")
        ]
    ),
    UnitDefinition(
        id: "falcarius", name: "Falcarius", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 300, baseStats: UnitStats(maxHP: 118, attackDamage: 24, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "early_scythe", name: "Early Scythe", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "Proto-claws, sharper strikes.")
        ]
    ),
    UnitDefinition(
        id: "guanlong", name: "Guanlong", era: .jurassic, sizeClass: .small, rarity: .rare,
        deployCost: 310, baseStats: UnitStats(maxHP: 126, attackDamage: 30, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "crest_caller", name: "Crest Caller", statModifiers: StatModifiers(attackDamage: 6), abilityDescription: "Bold display crest, bolder bite.")
        ]
    ),
    UnitDefinition(
        id: "eotyrannus", name: "Eotyrannus", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 310, baseStats: UnitStats(maxHP: 128, attackDamage: 30, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "proto_tyrant", name: "Proto Tyrant", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "Early tyrannosaur bite.")
        ]
    ),
    UnitDefinition(
        id: "thecodontosaurus", name: "Thecodontosaurus", era: .triassic, sizeClass: .small, rarity: .rare,
        deployCost: 300, baseStats: UnitStats(maxHP: 120, attackDamage: 26, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "ancestors_bite", name: "Ancestor's Bite", statModifiers: StatModifiers(attackDamage: 6), abilityDescription: "One of the earliest dinosaurs, sharper teeth.")
        ]
    ),
    UnitDefinition(
        id: "scelidosaurus", name: "Scelidosaurus", era: .jurassic, sizeClass: .small, rarity: .rare,
        deployCost: 320, baseStats: UnitStats(maxHP: 142, attackDamage: 24, attackIntervalSeconds: 0.95, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "early_armor", name: "Early Armor", statModifiers: StatModifiers(maxHP: 30), abilityDescription: "Thick early armor plating.")
        ]
    ),
    UnitDefinition(
        id: "minmi", name: "Minmi", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 320, baseStats: UnitStats(maxHP: 136, attackDamage: 22, attackIntervalSeconds: 0.95, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "belly_plate", name: "Belly Plate", statModifiers: StatModifiers(maxHP: 20), abilityDescription: "Underside armor, extra HP.")
        ]
    ),
    UnitDefinition(
        id: "masiakasaurus", name: "Masiakasaurus", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 310, baseStats: UnitStats(maxHP: 120, attackDamage: 30, attackIntervalSeconds: 0.85, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "needle_jaw", name: "Needle Jaw", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "Forward-jutting teeth, sharper bite.")
        ]
    ),
    UnitDefinition(
        id: "herrerasaurus", name: "Herrerasaurus", era: .triassic, sizeClass: .small, rarity: .rare,
        deployCost: 320, baseStats: UnitStats(maxHP: 135, attackDamage: 32, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "ancient_hunter", name: "Ancient Hunter", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "One of the first big predators, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "anzu", name: "Anzu", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 460, baseStats: UnitStats(maxHP: 340, attackDamage: 26, attackIntervalSeconds: 1.1, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "hell_chicken", name: "Hell Chicken", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Fast aggressive strikes.")
        ]
    ),
    UnitDefinition(
        id: "ornithomimus", name: "Ornithomimus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 420, baseStats: UnitStats(maxHP: 310, attackDamage: 20, attackIntervalSeconds: 1.1, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "ostrich_sprint", name: "Ostrich Sprint", statModifiers: StatModifiers(maxHP: 20), abilityDescription: "Built for speed and stamina.")
        ]
    ),
    UnitDefinition(
        id: "struthiomimus", name: "Struthiomimus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 420, baseStats: UnitStats(maxHP: 320, attackDamage: 20, attackIntervalSeconds: 1.1, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "swift_strider", name: "Swift Strider", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Long legs, faster strikes.")
        ]
    ),
    UnitDefinition(
        id: "gallimimus", name: "Gallimimus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 430, baseStats: UnitStats(maxHP: 330, attackDamage: 22, attackIntervalSeconds: 1.1, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "herd_runner", name: "Herd Runner", statModifiers: StatModifiers(maxHP: 30), abilityDescription: "Runs in herds, tougher.")
        ]
    ),
    UnitDefinition(
        id: "carnotaurus", name: "Carnotaurus", era: .cretaceous, sizeClass: .medium, rarity: .epic,
        deployCost: 560, baseStats: UnitStats(maxHP: 460, attackDamage: 42, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "devil_horn_charge", name: "Devil Horn Charge", statModifiers: StatModifiers(attackDamage: 10, grantsKnockbackAttack: true), abilityDescription: "Brow horns deliver a knockback charge.")
        ]
    ),
    UnitDefinition(
        id: "chasmosaurus", name: "Chasmosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 420, attackDamage: 32, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "great_frill", name: "Great Frill", statModifiers: StatModifiers(maxHP: 60), abilityDescription: "Enormous frill, tougher defense.")
        ]
    ),
    UnitDefinition(
        id: "einiosaurus", name: "Einiosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 400, attackDamage: 34, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "hook_horn", name: "Hook Horn", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Forward-curled horn knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "kosmoceratops", name: "Kosmoceratops", era: .cretaceous, sizeClass: .medium, rarity: .epic,
        deployCost: 590, baseStats: UnitStats(maxHP: 480, attackDamage: 36, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "ornate_crown", name: "Ornate Crown", statModifiers: StatModifiers(maxHP: 70), abilityDescription: "Elaborate horn crown, extra tough.")
        ]
    ),
    UnitDefinition(
        id: "diabloceratops", name: "Diabloceratops", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 510, baseStats: UnitStats(maxHP: 420, attackDamage: 36, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "devils_frill", name: "Devil's Frill", statModifiers: StatModifiers(attackDamage: 12), abilityDescription: "Sharp frill spikes, harder hits.")
        ]
    ),
    UnitDefinition(
        id: "zuniceratops", name: "Zuniceratops", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 460, baseStats: UnitStats(maxHP: 360, attackDamage: 28, attackIntervalSeconds: 1.2, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "first_horn", name: "First Horn", statModifiers: StatModifiers(maxHP: 40), abilityDescription: "Early horned dinosaur, sturdy.")
        ]
    ),
    UnitDefinition(
        id: "nasutoceratops", name: "Nasutoceratops", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 410, attackDamage: 32, attackIntervalSeconds: 1.2, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "big_nose_charge", name: "Big Nose Charge", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Powerful charge knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "regaliceratops", name: "Regaliceratops", era: .cretaceous, sizeClass: .medium, rarity: .epic,
        deployCost: 600, baseStats: UnitStats(maxHP: 470, attackDamage: 34, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "royal_crown", name: "Royal Crown", statModifiers: StatModifiers(maxHP: 80), abilityDescription: "Crown-shaped frill, extra tough.")
        ]
    ),
    UnitDefinition(
        id: "pachyrhinosaurus", name: "Pachyrhinosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 510, baseStats: UnitStats(maxHP: 430, attackDamage: 30, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "boss_nose_ram", name: "Boss Nose Ram", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Bony nose boss rams enemies back.")
        ]
    ),
    UnitDefinition(
        id: "sauropelta", name: "Sauropelta", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 520, baseStats: UnitStats(maxHP: 450, attackDamage: 26, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "spiked_hide", name: "Spiked Hide", statModifiers: StatModifiers(maxHP: 60), abilityDescription: "Rows of spikes add toughness.")
        ]
    ),
    UnitDefinition(
        id: "nodosaurus", name: "Nodosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 440, attackDamage: 24, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "plate_wall", name: "Plate Wall", statModifiers: StatModifiers(maxHP: 50), abilityDescription: "Thick dermal plates add toughness.")
        ]
    ),
    UnitDefinition(
        id: "gastonia", name: "Gastonia", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 510, baseStats: UnitStats(maxHP: 430, attackDamage: 28, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "shoulder_spikes", name: "Shoulder Spikes", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Shoulder spikes knock enemies back.")
        ]
    ),
    UnitDefinition(
        id: "polacanthus", name: "Polacanthus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 420, attackDamage: 26, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "pelvic_shield", name: "Pelvic Shield", statModifiers: StatModifiers(maxHP: 50), abilityDescription: "Fused pelvic armor, extra tough.")
        ]
    ),
    UnitDefinition(
        id: "huayangosaurus", name: "Huayangosaurus", era: .jurassic, sizeClass: .medium, rarity: .common,
        deployCost: 460, baseStats: UnitStats(maxHP: 360, attackDamage: 30, attackIntervalSeconds: 1.2, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "early_plate", name: "Early Plate", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "Early stegosaur spikes, sharper hits.")
        ]
    ),
    UnitDefinition(
        id: "tuojiangosaurus", name: "Tuojiangosaurus", era: .jurassic, sizeClass: .medium, rarity: .rare,
        deployCost: 520, baseStats: UnitStats(maxHP: 440, attackDamage: 34, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "twin_spike_tail", name: "Twin Spike Tail", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Tail spikes knock enemies back.")
        ]
    ),
    UnitDefinition(
        id: "kentrosaurus", name: "Kentrosaurus", era: .jurassic, sizeClass: .medium, rarity: .rare,
        deployCost: 510, baseStats: UnitStats(maxHP: 420, attackDamage: 32, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "shoulder_spike_guard", name: "Shoulder Spike Guard", statModifiers: StatModifiers(maxHP: 50), abilityDescription: "Shoulder spikes add defense.")
        ]
    ),
    UnitDefinition(
        id: "riojasaurus", name: "Riojasaurus", era: .triassic, sizeClass: .medium, rarity: .common,
        deployCost: 450, baseStats: UnitStats(maxHP: 380, attackDamage: 26, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "early_giant", name: "Early Giant", statModifiers: StatModifiers(maxHP: 50), abilityDescription: "One of the first giants, tougher.")
        ]
    ),
    UnitDefinition(
        id: "massospondylus", name: "Massospondylus", era: .triassic, sizeClass: .medium, rarity: .common,
        deployCost: 440, baseStats: UnitStats(maxHP: 360, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "long_neck_browser", name: "Long Neck Browser", statModifiers: StatModifiers(maxHP: 40), abilityDescription: "Reaches higher, sturdier build.")
        ]
    ),
    UnitDefinition(
        id: "lufengosaurus", name: "Lufengosaurus", era: .triassic, sizeClass: .medium, rarity: .common,
        deployCost: 450, baseStats: UnitStats(maxHP: 370, attackDamage: 26, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "dawn_grazer", name: "Dawn Grazer", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "One of the earliest big herbivores, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "yangchuanosaurus", name: "Yangchuanosaurus", era: .jurassic, sizeClass: .medium, rarity: .rare,
        deployCost: 540, baseStats: UnitStats(maxHP: 420, attackDamage: 40, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "eastern_predator", name: "Eastern Predator", statModifiers: StatModifiers(attackDamage: 12), abilityDescription: "Asia's apex Jurassic hunter, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "baryonyx", name: "Baryonyx", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 540, baseStats: UnitStats(maxHP: 430, attackDamage: 36, attackIntervalSeconds: 1.1, rangeUnits: 1.2),
        evolutionBranches: [
            EvolutionBranch(id: "fish_hook_claw", name: "Fish Hook Claw", statModifiers: StatModifiers(attackDamage: 10), abilityDescription: "Massive thumb claw, sharper strikes.")
        ]
    ),
    UnitDefinition(
        id: "skorpiovenator", name: "Skorpiovenator", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 500, baseStats: UnitStats(maxHP: 400, attackDamage: 36, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "scorpion_strike", name: "Scorpion Strike", statModifiers: StatModifiers(attackDamage: 10), abilityDescription: "Bony-faced hunter, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "aucasaurus", name: "Aucasaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 490, baseStats: UnitStats(maxHP: 390, attackDamage: 34, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "pack_stalker", name: "Pack Stalker", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "Coordinated hunting, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "nigersaurus", name: "Nigersaurus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 470, baseStats: UnitStats(maxHP: 370, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "wide_grazer", name: "Wide Grazer", statModifiers: StatModifiers(maxHP: 30), abilityDescription: "Wide mouth, sturdier grazer.")
        ]
    ),
    UnitDefinition(
        id: "europasaurus", name: "Europasaurus", era: .jurassic, sizeClass: .medium, rarity: .common,
        deployCost: 460, baseStats: UnitStats(maxHP: 360, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "island_dwarf", name: "Island Dwarf", statModifiers: StatModifiers(maxHP: 40), abilityDescription: "Compact island sauropod, surprisingly tough.")
        ]
    ),
    UnitDefinition(
        id: "edmontosaurus", name: "Edmontosaurus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 450, baseStats: UnitStats(maxHP: 340, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "duck_bill_herd", name: "Duck-Bill Herd", statModifiers: StatModifiers(maxHP: 40), abilityDescription: "Herd instincts, tougher.")
        ]
    ),
    UnitDefinition(
        id: "corythosaurus", name: "Corythosaurus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 460, baseStats: UnitStats(maxHP: 350, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "helmet_crest_call", name: "Helmet Crest Call", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Resonant crest call, faster strikes.")
        ]
    ),
    UnitDefinition(
        id: "lambeosaurus", name: "Lambeosaurus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 460, baseStats: UnitStats(maxHP: 350, attackDamage: 24, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "hatchet_crest", name: "Hatchet Crest", statModifiers: StatModifiers(maxHP: 30), abilityDescription: "Distinct crest shape, sturdier build.")
        ]
    ),
    UnitDefinition(
        id: "saurolophus", name: "Saurolophus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 480, baseStats: UnitStats(maxHP: 380, attackDamage: 28, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "spike_crest_charge", name: "Spike Crest Charge", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Spike-crested charge knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "camptosaurus", name: "Camptosaurus", era: .jurassic, sizeClass: .medium, rarity: .common,
        deployCost: 440, baseStats: UnitStats(maxHP: 330, attackDamage: 22, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "grazers_guard", name: "Grazer's Guard", statModifiers: StatModifiers(maxHP: 30), abilityDescription: "Sturdy grazer, extra tough.")
        ]
    ),
    UnitDefinition(
        id: "tenontosaurus", name: "Tenontosaurus", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 450, baseStats: UnitStats(maxHP: 360, attackDamage: 26, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "thick_tail_whip", name: "Thick Tail Whip", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Heavy tail whip knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "maiasaura", name: "Maiasaura", era: .cretaceous, sizeClass: .medium, rarity: .common,
        deployCost: 460, baseStats: UnitStats(maxHP: 370, attackDamage: 22, attackIntervalSeconds: 1.2, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "good_mother", name: "Good Mother", statModifiers: StatModifiers(maxHP: 50), abilityDescription: "Nurturing instincts, tougher.")
        ]
    ),
    UnitDefinition(
        id: "therizinosaurus", name: "Therizinosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 800, baseStats: UnitStats(maxHP: 760, attackDamage: 50, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "scythe_reach", name: "Scythe Reach", statModifiers: StatModifiers(attackDamage: 10), abilityDescription: "Massive scythe claws, harder hits.")
        ]
    ),
    UnitDefinition(
        id: "giganotosaurus", name: "Giganotosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 830, baseStats: UnitStats(maxHP: 800, attackDamage: 68, attackIntervalSeconds: 1.5, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "southern_titan", name: "Southern Titan", statModifiers: StatModifiers(attackDamage: 20), abilityDescription: "One of the largest predators, devastating bite.")
        ]
    ),
    UnitDefinition(
        id: "miragaia", name: "Miragaia", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 760, baseStats: UnitStats(maxHP: 720, attackDamage: 48, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "long_plate_neck", name: "Long Plate Neck", statModifiers: StatModifiers(maxHP: 60), abilityDescription: "Elongated plated neck, tougher.")
        ]
    ),
    UnitDefinition(
        id: "camarasaurus", name: "Camarasaurus", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 750, baseStats: UnitStats(maxHP: 740, attackDamage: 46, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "sturdy_grazer", name: "Sturdy Grazer", statModifiers: StatModifiers(maxHP: 80), abilityDescription: "Robust build, extra tough.")
        ]
    ),
    UnitDefinition(
        id: "diplodocus", name: "Diplodocus", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 760, baseStats: UnitStats(maxHP: 750, attackDamage: 44, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "whip_tail", name: "Whip Tail", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Long tail cracks like a whip.")
        ]
    ),
    UnitDefinition(
        id: "apatosaurus", name: "Apatosaurus", era: .jurassic, sizeClass: .large, rarity: .epic,
        deployCost: 800, baseStats: UnitStats(maxHP: 800, attackDamage: 52, attackIntervalSeconds: 1.6, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "thunder_stomp", name: "Thunder Stomp", statModifiers: StatModifiers(attackDamage: 10, grantsKnockbackAttack: true), abilityDescription: "Ground-shaking stomp knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "barosaurus", name: "Barosaurus", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 770, baseStats: UnitStats(maxHP: 760, attackDamage: 46, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "rearing_guard", name: "Rearing Guard", statModifiers: StatModifiers(maxHP: 70), abilityDescription: "Rears up defensively, tougher.")
        ]
    ),
    UnitDefinition(
        id: "amargasaurus", name: "Amargasaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 790, baseStats: UnitStats(maxHP: 730, attackDamage: 50, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "twin_sail_spine", name: "Twin Sail Spine", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Spined sails lash back at attackers.")
        ]
    ),
    UnitDefinition(
        id: "yutyrannus", name: "Yutyrannus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 810, baseStats: UnitStats(maxHP: 780, attackDamage: 55, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "feathered_tyrant", name: "Feathered Tyrant", statModifiers: StatModifiers(attackDamage: 15), abilityDescription: "Largest feathered predator known, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "daspletosaurus", name: "Daspletosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 820, baseStats: UnitStats(maxHP: 790, attackDamage: 58, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "frightful_bite", name: "Frightful Bite", statModifiers: StatModifiers(attackDamage: 18), abilityDescription: "Bone-crushing bite force.")
        ]
    ),
    UnitDefinition(
        id: "tarbosaurus", name: "Tarbosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 830, baseStats: UnitStats(maxHP: 800, attackDamage: 60, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "eastern_tyrant", name: "Eastern Tyrant", statModifiers: StatModifiers(attackDamage: 20), abilityDescription: "Asia's tyrant king, devastating bite.")
        ]
    ),
    UnitDefinition(
        id: "gorgosaurus", name: "Gorgosaurus", era: .cretaceous, sizeClass: .large, rarity: .rare,
        deployCost: 780, baseStats: UnitStats(maxHP: 750, attackDamage: 52, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "fierce_lizard", name: "Fierce Lizard", statModifiers: StatModifiers(attackDamage: 14), abilityDescription: "Fast fierce hunter, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "albertosaurus", name: "Albertosaurus", era: .cretaceous, sizeClass: .large, rarity: .rare,
        deployCost: 770, baseStats: UnitStats(maxHP: 740, attackDamage: 50, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "northern_hunter", name: "Northern Hunter", statModifiers: StatModifiers(attackDamage: 12), abilityDescription: "Pack hunter, harder bite.")
        ]
    ),
    UnitDefinition(
        id: "qianzhousaurus", name: "Qianzhousaurus", era: .cretaceous, sizeClass: .large, rarity: .rare,
        deployCost: 760, baseStats: UnitStats(maxHP: 720, attackDamage: 48, attackIntervalSeconds: 1.4, rangeUnits: 1.2, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "long_snout_snap", name: "Long Snout Snap", statModifiers: StatModifiers(attackDamage: 8), abilityDescription: "'Pinocchio rex' snout, quick sharp bites.")
        ]
    ),
    UnitDefinition(
        id: "alioramus", name: "Alioramus", era: .cretaceous, sizeClass: .large, rarity: .rare,
        deployCost: 760, baseStats: UnitStats(maxHP: 720, attackDamage: 46, attackIntervalSeconds: 1.4, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "slender_tyrant", name: "Slender Tyrant", statModifiers: StatModifiers(attackIntervalSeconds: -0.1), abilityDescription: "Slender build, faster strikes.")
        ]
    ),
    UnitDefinition(
        id: "deinocheirus", name: "Deinocheirus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 800, baseStats: UnitStats(maxHP: 780, attackDamage: 44, attackIntervalSeconds: 1.5, rangeUnits: 1.2, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "giant_claw_reach", name: "Giant Claw Reach", statModifiers: StatModifiers(attackDamage: 12), abilityDescription: "Enormous claws, harder hits.")
        ]
    ),
    UnitDefinition(
        id: "shantungosaurus", name: "Shantungosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 850, baseStats: UnitStats(maxHP: 820, attackDamage: 56, attackIntervalSeconds: 1.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "giant_duck_bill", name: "Giant Duck-Bill", statModifiers: StatModifiers(maxHP: 100), abilityDescription: "Largest known hadrosaur, extra tough.")
        ]
    ),
    UnitDefinition(
        id: "argentinosaurus", name: "Argentinosaurus", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1950, baseStats: UnitStats(maxHP: 2100, attackDamage: 140, attackIntervalSeconds: 2.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "colossal_titan", name: "Colossal Titan", statModifiers: StatModifiers(maxHP: 400), abilityDescription: "One of the largest land animals ever, immense HP."),
            EvolutionBranch(id: "earth_shaker", name: "Earth-Shaker", statModifiers: StatModifiers(attackDamage: 20, grantsKnockbackAttack: true), abilityDescription: "Titanic footfalls knock enemies back.")
        ]
    ),
    UnitDefinition(
        id: "patagotitan", name: "Patagotitan", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1900, baseStats: UnitStats(maxHP: 2050, attackDamage: 138, attackIntervalSeconds: 2.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "patagonian_giant", name: "Patagonian Giant", statModifiers: StatModifiers(maxHP: 350), abilityDescription: "Among the heaviest titanosaurs, extra HP."),
            EvolutionBranch(id: "record_breaker", name: "Record Breaker", statModifiers: StatModifiers(attackDamage: 25), abilityDescription: "Among the heaviest animals ever, raw crushing power.")
        ]
    ),
    UnitDefinition(
        id: "dreadnoughtus", name: "Dreadnoughtus", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1880, baseStats: UnitStats(maxHP: 2000, attackDamage: 135, attackIntervalSeconds: 2.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "fearless_titan", name: "Fearless Titan", statModifiers: StatModifiers(attackDamage: 20), abilityDescription: "True to its name, hits devastatingly hard."),
            EvolutionBranch(id: "nothing_to_fear", name: "Nothing to Fear", statModifiers: StatModifiers(maxHP: 300), abilityDescription: "Utterly unbothered by threats, even more HP.")
        ]
    ),
    UnitDefinition(
        id: "mamenchisaurus", name: "Mamenchisaurus", era: .jurassic, sizeClass: .apex, rarity: .legendary,
        deployCost: 1750, baseStats: UnitStats(maxHP: 1900, attackDamage: 130, attackIntervalSeconds: 2.4, rangeUnits: 1.2, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "longest_neck", name: "Longest Neck", statModifiers: StatModifiers(maxHP: 250), abilityDescription: "Longest neck of any dinosaur, extra reach and HP."),
            EvolutionBranch(id: "neck_whip", name: "Neck Whip", statModifiers: StatModifiers(grantsKnockbackAttack: true), abilityDescription: "Swings its immense neck like a whip, knocking enemies back.")
        ]
    ),
    UnitDefinition(
        id: "supersaurus", name: "Supersaurus", era: .jurassic, sizeClass: .apex, rarity: .legendary,
        deployCost: 1850, baseStats: UnitStats(maxHP: 2000, attackDamage: 135, attackIntervalSeconds: 2.5, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "super_giant", name: "Super Giant", statModifiers: StatModifiers(maxHP: 350), abilityDescription: "One of the longest dinosaurs ever, immense HP."),
            EvolutionBranch(id: "ground_tremor", name: "Ground Tremor", statModifiers: StatModifiers(attackDamage: 15, grantsKnockbackAttack: true), abilityDescription: "Every step shakes the ground, knocking enemies back.")
        ]
    ),
    UnitDefinition(
        id: "giraffatitan", name: "Giraffatitan", era: .jurassic, sizeClass: .apex, rarity: .legendary,
        deployCost: 1780, baseStats: UnitStats(maxHP: 1950, attackDamage: 132, attackIntervalSeconds: 2.4, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "towering_grazer", name: "Towering Grazer", statModifiers: StatModifiers(maxHP: 300), abilityDescription: "Towering brachiosaurid, immense HP."),
            EvolutionBranch(id: "canopy_reach", name: "Canopy Reach", statModifiers: StatModifiers(attackDamage: 18), abilityDescription: "Browses the highest canopy, hits harder.")
        ]
    )
]

/// Battle Cats-style automatic evolution: a unit's Enhance level decides which form it deploys
/// as, instead of every branch being its own deploy button (which made the old deploy bar
/// unusably long -- 200+ buttons at 100 units). Level 5 unlocks the first evolution branch,
/// max level unlocks the second (SSR units only, they're the ones with two branches). The real
/// design's Evolution Catalysts (GAME_DESIGN.md §5) can replace this rule later; the milestone
/// idea is the same, this just keys it to Enhance progress the way Battle Cats keys it to XP.
func autoEvolutionBranchID(for unit: UnitDefinition, enhancementLevel: Int) -> String? {
    guard !unit.evolutionBranches.isEmpty else { return nil }
    if enhancementLevel >= PlayerProfile.maxLevel, unit.evolutionBranches.count >= 2 {
        return unit.evolutionBranches[1].id
    }
    if enhancementLevel >= 5 {
        return unit.evolutionBranches[0].id
    }
    return nil
}

// MARK: - SpriteKit battle scene

final class BattleScene: SKScene, ObservableObject {
    private let startingBaseHP = 1000
    private var lane = Lane(length: 750, playerBaseHP: 1000, enemyBaseHP: 1000)
    // (kept as literal 1000 above since stored-property initializers can't reference sibling
    // properties -- `startingBaseHP` is used everywhere else: reset(), endGameByTimeLimit())
    private var lastUpdateTime: TimeInterval?

    // An 8-minute match clock: if neither base is destroyed by then, whoever dealt more
    // cumulative damage to the opposing base wins (a draw if exactly tied). The last 3 minutes
    // double both sides' Amber income, so the match has a real climax instead of just petering
    // out if it runs long.
    private var matchElapsedTime: Double = 0
    private let matchDurationSeconds: Double = 480
    private let doubleAmberStartSeconds: Double = 300
    private var isInDoubleAmberPhase: Bool { matchElapsedTime >= doubleAmberStartSeconds }
    // Raised from the default 10 during the double-Amber final stretch, so faster income also
    // comes with room to actually field more/bigger units instead of just refilling faster.
    private static let doubleAmberPhaseFrontlineBUCap = 16

    // Amber is tracked as a whole number (it was only ever displayed as Int anyway) and
    // @Published is only updated when that whole number actually changes -- publishing every
    // frame at 60fps just to grey out buttons would be wasteful and can visibly stutter SwiftUI.
    private var amberAccumulator: Double = 0
    @Published private(set) var amber: Int = 0
    // Was 20/sec, dropped to 12/sec after the first playtest (20 was too fast), then dropped
    // further to 8/sec -- that turned out too slow, so back to 12/sec. Now a `var`, not a `let`,
    // because Upgrade Base (Battle Cats-style) permanently raises it for the rest of the match.
    private let baseAmberPerSecond: Double = 12
    private var amberPerSecond: Double = 12

    // Battle Cats-style base upgrade: spend Amber to permanently raise income for the rest of
    // the match, so bigger/expensive units become reachable later on instead of the economy
    // staying flat the whole game. Cost scales up each level so it's a real decision, not a
    // no-brainer to spam immediately.
    @Published private(set) var baseLevel: Int = 1
    private let amberPerSecondPerUpgrade: Double = 2
    var baseUpgradeCost: Int { 150 * baseLevel }

    func upgradeBase() {
        guard !isGameOver, amber >= baseUpgradeCost else { return }
        amber -= baseUpgradeCost
        amberAccumulator = Double(amber)
        amberPerSecond += amberPerSecondPerUpgrade
        baseLevel += 1
    }

    // A manual, one-shot base attack -- Battle Cats' Cat Cannon equivalent. Free (no Amber
    // cost), but usable exactly once per match, so it's a save-it-for-the-right-moment tool
    // rather than another thing to spend income on.
    @Published private(set) var baseAttackUsed = false
    private let baseAttackDamage = 300

    func fireBaseAttack() {
        guard !isGameOver, !baseAttackUsed else { return }
        lane.dealDamageToBase(baseAttackDamage, of: .enemy)
        baseAttackUsed = true
    }

    // Which campaign stage this match is (1-based). Set once by BattleView before the scene is
    // presented; drives enemy difficulty and the enemy base's look, and deliberately survives
    // `reset()` so "Play Again" replays the same stage.
    var campaignLevel: Int = 1

    // The enemy has its own economy now, gated the same way the player's is -- previously this
    // spawned a uniformly random unit (including the 1800-cost T. Rex) every 2 seconds with no
    // cost check at all, which made the game unwinnable regardless of player skill. Now it can
    // only deploy what it can actually afford, and both its income and how expensive a unit it's
    // allowed to field scale with the campaign stage: stage 1 is a slow trickle of cheap units,
    // the final stage out-earns the player's base income and can afford the apex titans.
    private var enemyAmberAccumulator: Double = 0
    private var enemyAmberPerSecond: Double { 6.0 + 1.5 * Double(campaignLevel) }
    private var enemyMaxUnitCost: Int { 400 + campaignLevel * 180 }
    private var enemySpawnCheckTimer: Double = 0
    private let enemySpawnCheckInterval: Double = 0.5

    @Published private(set) var isGameOver = false

    private struct UnitVisual {
        let container: SKNode
        let hpLabel: SKLabelNode
    }
    private var playerVisuals: [UUID: UnitVisual] = [:]
    private var enemyVisuals: [UUID: UnitVisual] = [:]

    private let amberLabel = SKLabelNode(fontNamed: "Menlo")
    private let stageLabel = SKLabelNode(fontNamed: "Menlo")
    private let playerBaseLabel = SKLabelNode(fontNamed: "Menlo")
    private let enemyBaseLabel = SKLabelNode(fontNamed: "Menlo")
    private let statusLabel = SKLabelNode(fontNamed: "Menlo")
    private let statusBacking = SKShapeNode(rectOf: CGSize(width: 260, height: 50), cornerRadius: 10)
    private let timeLabel = SKLabelNode(fontNamed: "Menlo")
    private let synergyLabel = SKLabelNode(fontNamed: "Menlo")

    // Battle Cats HUD arrangement: stage name top-left, money (Amber) top-right, clock centered,
    // and each base's HP floating directly above its own tower instead of parked in a corner.
    override func didMove(to view: SKView) {
        backgroundColor = .black
        buildScenery()
        buildBases()

        stageLabel.fontSize = 16
        stageLabel.fontColor = .white
        stageLabel.horizontalAlignmentMode = .left
        stageLabel.position = CGPoint(x: 20, y: size.height - 30)
        stageLabel.text = "Stage \(campaignLevel)"
        addChild(stageLabel)

        amberLabel.fontSize = 18
        amberLabel.fontColor = SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)
        amberLabel.horizontalAlignmentMode = .right
        amberLabel.position = CGPoint(x: size.width - 20, y: size.height - 30)
        addChild(amberLabel)

        playerBaseLabel.fontSize = 12
        playerBaseLabel.fontColor = .white
        playerBaseLabel.horizontalAlignmentMode = .center
        playerBaseLabel.position = CGPoint(x: xPosition(for: 0), y: size.height / 2 + 68)
        addChild(playerBaseLabel)

        enemyBaseLabel.fontSize = 12
        enemyBaseLabel.fontColor = .white
        enemyBaseLabel.horizontalAlignmentMode = .center
        enemyBaseLabel.position = CGPoint(x: xPosition(for: lane.length), y: size.height / 2 + 68)
        addChild(enemyBaseLabel)

        timeLabel.fontSize = 18
        timeLabel.horizontalAlignmentMode = .center
        timeLabel.position = CGPoint(x: size.width / 2, y: size.height - 30)
        addChild(timeLabel)

        synergyLabel.fontSize = 14
        synergyLabel.fontColor = .systemYellow
        synergyLabel.horizontalAlignmentMode = .center
        synergyLabel.position = CGPoint(x: size.width / 2, y: size.height - 55)
        addChild(synergyLabel)

        statusBacking.fillColor = SKColor.black.withAlphaComponent(0.55)
        statusBacking.strokeColor = .clear
        statusBacking.position = CGPoint(x: size.width / 2, y: size.height / 2)
        statusBacking.zPosition = 7
        statusBacking.isHidden = true
        addChild(statusBacking)

        statusLabel.fontSize = 32
        statusLabel.fontColor = .white
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        statusLabel.zPosition = 8
        statusLabel.isHidden = true
        addChild(statusLabel)

        let hudBacking = SKShapeNode(rectOf: CGSize(width: size.width, height: 62), cornerRadius: 0)
        hudBacking.fillColor = SKColor.black.withAlphaComponent(0.35)
        hudBacking.strokeColor = .clear
        hudBacking.position = CGPoint(x: size.width / 2, y: size.height - 30)
        hudBacking.zPosition = 5
        addChild(hudBacking)
        [amberLabel, stageLabel, playerBaseLabel, enemyBaseLabel, timeLabel, synergyLabel].forEach { $0.zPosition = 6 }
    }

    /// Placeholder environment art -- no real illustrated backgrounds exist yet (see
    /// `docs/ART_BIBLE.md` §5), but a flat black `SKScene` reads as broken/unfinished rather
    /// than "no art yet." This is all procedural (a CoreGraphics-rendered sky gradient plus
    /// SpriteKit shape primitives for the ground/mountains/foliage), so it needs zero external
    /// assets and can't be blocked by image-generation credits the way real art is.
    private func buildScenery() {
        let skyTexture = Self.gradientTexture(
            size: size,
            colors: [
                SKColor(red: 0.55, green: 0.78, blue: 0.92, alpha: 1),
                SKColor(red: 0.98, green: 0.87, blue: 0.6, alpha: 1),
                SKColor(red: 0.62, green: 0.78, blue: 0.56, alpha: 1)
            ]
        )
        let sky = SKSpriteNode(texture: skyTexture, size: size)
        sky.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sky.zPosition = -100
        addChild(sky)

        let sun = SKShapeNode(circleOfRadius: 24)
        sun.fillColor = SKColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 0.95)
        sun.strokeColor = .clear
        sun.glowWidth = 14
        sun.position = CGPoint(x: size.width * 0.85, y: size.height * 0.85)
        sun.zPosition = -92
        addChild(sun)

        // Soft drifting clouds -- purely decorative, breaks up the flat sky gradient a bit.
        let cloudColor = SKColor.white.withAlphaComponent(0.6)
        let cloudSpecs: [(xFraction: CGFloat, yFraction: CGFloat, scale: CGFloat)] = [
            (0.18, 0.9, 1.0), (0.55, 0.94, 0.7), (0.85, 0.8, 0.85)
        ]
        for spec in cloudSpecs {
            let cloud = SKNode()
            let puffSpecs: [(dx: CGFloat, dy: CGFloat, r: CGFloat)] = [
                (-14, 0, 12), (0, 5, 16), (14, 0, 12)
            ]
            for puffSpec in puffSpecs {
                let puff = SKShapeNode(circleOfRadius: puffSpec.r * spec.scale)
                puff.fillColor = cloudColor
                puff.strokeColor = .clear
                puff.position = CGPoint(x: puffSpec.dx * spec.scale, y: puffSpec.dy * spec.scale)
                cloud.addChild(puff)
            }
            cloud.position = CGPoint(x: size.width * spec.xFraction, y: size.height * spec.yFraction)
            cloud.zPosition = -95
            addChild(cloud)
        }

        // Rounded hill silhouettes (a quad curve instead of a sharp triangle) -- reads as toy-like
        // and chibi per ART_BIBLE.md §1 instead of jagged mountains.
        let hillColor = SKColor(red: 0.4, green: 0.56, blue: 0.36, alpha: 0.6)
        for (xFraction, peakHeight, widthFraction) in [(0.15, 90.0, 0.42), (0.78, 75.0, 0.4)] {
            let baseY = size.height / 2 + 10
            let centerX = size.width * CGFloat(xFraction)
            let halfWidth = size.width * CGFloat(widthFraction) / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: centerX - halfWidth, y: baseY))
            path.addQuadCurve(
                to: CGPoint(x: centerX + halfWidth, y: baseY),
                control: CGPoint(x: centerX, y: baseY + CGFloat(peakHeight) * 1.3)
            )
            path.closeSubpath()
            let hill = SKShapeNode(path: path)
            hill.fillColor = hillColor
            hill.strokeColor = .clear
            hill.zPosition = -80
            addChild(hill)
        }

        // The one landmark that says "prehistoric" at a glance: a smoking volcano on the horizon,
        // center-frame between the two hills. This backdrop is deliberately the SAME on every
        // campaign stage -- only the enemy base changes per stage (see buildBases), Battle
        // Cats-style, so stages read as different places without a whole new map each time.
        let volcanoBaseY = size.height / 2 + 10
        let volcanoCenterX = size.width * 0.45
        let volcanoHalfWidth = size.width * 0.16
        let volcanoHeight: CGFloat = 130
        let craterHalfWidth: CGFloat = 16
        let volcanoPath = CGMutablePath()
        volcanoPath.move(to: CGPoint(x: volcanoCenterX - volcanoHalfWidth, y: volcanoBaseY))
        volcanoPath.addQuadCurve(
            to: CGPoint(x: volcanoCenterX - craterHalfWidth, y: volcanoBaseY + volcanoHeight),
            control: CGPoint(x: volcanoCenterX - volcanoHalfWidth * 0.55, y: volcanoBaseY + volcanoHeight * 0.45)
        )
        volcanoPath.addLine(to: CGPoint(x: volcanoCenterX + craterHalfWidth, y: volcanoBaseY + volcanoHeight))
        volcanoPath.addQuadCurve(
            to: CGPoint(x: volcanoCenterX + volcanoHalfWidth, y: volcanoBaseY),
            control: CGPoint(x: volcanoCenterX + volcanoHalfWidth * 0.55, y: volcanoBaseY + volcanoHeight * 0.45)
        )
        volcanoPath.closeSubpath()
        let volcano = SKShapeNode(path: volcanoPath)
        volcano.fillColor = SKColor(red: 0.45, green: 0.34, blue: 0.3, alpha: 0.85)
        volcano.strokeColor = .clear
        volcano.zPosition = -85
        addChild(volcano)

        let craterGlow = SKShapeNode(ellipseOf: CGSize(width: craterHalfWidth * 2.4, height: 10))
        craterGlow.fillColor = SKColor(red: 1.0, green: 0.45, blue: 0.15, alpha: 0.9)
        craterGlow.strokeColor = .clear
        craterGlow.glowWidth = 5
        craterGlow.position = CGPoint(x: volcanoCenterX, y: volcanoBaseY + volcanoHeight)
        craterGlow.zPosition = -84
        addChild(craterGlow)

        for (index, puffSpec) in [(0, 10.0), (1, 7.0), (2, 5.0)].enumerated() {
            let puff = SKShapeNode(circleOfRadius: CGFloat(puffSpec.1))
            puff.fillColor = SKColor(white: 0.45, alpha: 0.5)
            puff.strokeColor = .clear
            puff.position = CGPoint(
                x: volcanoCenterX + CGFloat(index) * 12,
                y: volcanoBaseY + volcanoHeight + 14 + CGFloat(index) * 14
            )
            puff.zPosition = -86
            addChild(puff)
        }

        // The ground band units actually walk along -- matches the `altitudeOffset` baseline
        // in `sync(units:visuals:sideColor:)` so units visibly stand on it instead of floating.
        let ground = SKShapeNode(rectOf: CGSize(width: size.width, height: 70))
        ground.fillColor = SKColor(red: 0.48, green: 0.37, blue: 0.22, alpha: 1)
        ground.strokeColor = .clear
        ground.position = CGPoint(x: size.width / 2, y: size.height / 2)
        ground.zPosition = -50
        addChild(ground)

        // A thin lighter strip along the top edge of the ground band reads as grass overhanging
        // the dirt, cheap but effective toy-diorama depth cue.
        let grassEdge = SKShapeNode(rectOf: CGSize(width: size.width, height: 10))
        grassEdge.fillColor = SKColor(red: 0.42, green: 0.62, blue: 0.32, alpha: 0.9)
        grassEdge.strokeColor = .clear
        grassEdge.position = CGPoint(x: size.width / 2, y: size.height / 2 + 35)
        grassEdge.zPosition = -49
        addChild(grassEdge)

        // Fern clusters instead of anonymous shrub blobs -- three fronds fanning out of one
        // point reads as prehistoric undergrowth even at this tiny size.
        let frondColor = SKColor(red: 0.24, green: 0.48, blue: 0.24, alpha: 0.9)
        let fernXFractions: [CGFloat] = [0.08, 0.22, 0.38, 0.62, 0.78, 0.92]
        for xFraction in fernXFractions {
            let fern = SKNode()
            for rotation in [-0.7, 0.0, 0.7] {
                let frond = SKShapeNode(ellipseOf: CGSize(width: 6, height: 22))
                frond.fillColor = frondColor
                frond.strokeColor = .clear
                frond.zRotation = CGFloat(rotation)
                frond.position = CGPoint(x: CGFloat(rotation) * 9, y: 8)
                fern.addChild(frond)
            }
            fern.position = CGPoint(x: size.width * xFraction, y: size.height / 2 - 32)
            fern.zPosition = -40
            addChild(fern)
        }
    }

    /// Battle Cats-style base towers at each lane end: the player's dino den is the same every
    /// stage (it's YOUR base), while the enemy base cycles through four looks by stage number --
    /// per the direction that campaign stages should read as different maps via their bases
    /// alone, without needing a whole new background per stage yet.
    private func buildBases() {
        let groundY = size.height / 2 - 25

        // Player base (right edge): a warm-brown dino den with a domed roof, doorway, and the
        // one-shot bone cannon perched on top (it's the Fire Base Attack button's visual anchor).
        let playerBase = SKNode()
        let denBody = SKShapeNode(rectOf: CGSize(width: 54, height: 52), cornerRadius: 10)
        denBody.fillColor = SKColor(red: 0.78, green: 0.6, blue: 0.4, alpha: 1)
        denBody.strokeColor = SKColor(red: 0.45, green: 0.3, blue: 0.16, alpha: 1)
        denBody.lineWidth = 3
        denBody.position = CGPoint(x: 0, y: 26)
        playerBase.addChild(denBody)

        let denRoof = SKShapeNode(ellipseOf: CGSize(width: 62, height: 30))
        denRoof.fillColor = SKColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
        denRoof.strokeColor = SKColor(red: 0.4, green: 0.26, blue: 0.14, alpha: 1)
        denRoof.lineWidth = 3
        denRoof.position = CGPoint(x: 0, y: 52)
        playerBase.addChild(denRoof)

        let denDoor = SKShapeNode(rectOf: CGSize(width: 18, height: 24), cornerRadius: 8)
        denDoor.fillColor = SKColor(red: 0.25, green: 0.16, blue: 0.1, alpha: 1)
        denDoor.strokeColor = .clear
        denDoor.position = CGPoint(x: 0, y: 12)
        playerBase.addChild(denDoor)

        let cannon = SKShapeNode(rectOf: CGSize(width: 22, height: 8), cornerRadius: 4)
        cannon.fillColor = SKColor(red: 0.92, green: 0.9, blue: 0.82, alpha: 1)
        cannon.strokeColor = SKColor(red: 0.5, green: 0.45, blue: 0.4, alpha: 1)
        cannon.lineWidth = 2
        cannon.zRotation = 0.35
        cannon.position = CGPoint(x: -14, y: 66)
        playerBase.addChild(cannon)

        playerBase.position = CGPoint(x: xPosition(for: 0), y: groundY)
        playerBase.zPosition = -30
        addChild(playerBase)

        // Enemy base (left edge), themed by stage.
        let enemyBase = buildEnemyBaseNode(theme: (campaignLevel - 1) % 4)
        enemyBase.position = CGPoint(x: xPosition(for: lane.length), y: groundY)
        enemyBase.zPosition = -30
        addChild(enemyBase)
    }

    /// The four rotating enemy base looks: 0 = egg nest, 1 = stone spire, 2 = jungle totem,
    /// 3 = magma fort. Stage 1 starts at the nest and the cycle repeats every four stages.
    private func buildEnemyBaseNode(theme: Int) -> SKNode {
        let node = SKNode()
        switch theme {
        case 0:
            let mound = SKShapeNode(ellipseOf: CGSize(width: 72, height: 44))
            mound.fillColor = SKColor(red: 0.6, green: 0.45, blue: 0.28, alpha: 1)
            mound.strokeColor = SKColor(red: 0.42, green: 0.3, blue: 0.17, alpha: 1)
            mound.lineWidth = 3
            mound.position = CGPoint(x: 0, y: 20)
            node.addChild(mound)
            for (dx, tilt) in [(-16.0, -0.2), (0.0, 0.0), (16.0, 0.2)] {
                let egg = SKShapeNode(ellipseOf: CGSize(width: 16, height: 22))
                egg.fillColor = SKColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1)
                egg.strokeColor = SKColor(red: 0.6, green: 0.55, blue: 0.45, alpha: 1)
                egg.lineWidth = 2
                egg.zRotation = CGFloat(tilt)
                egg.position = CGPoint(x: CGFloat(dx), y: 44)
                node.addChild(egg)
            }
        case 1:
            let spire = SKShapeNode(rectOf: CGSize(width: 44, height: 74), cornerRadius: 8)
            spire.fillColor = SKColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
            spire.strokeColor = SKColor(red: 0.35, green: 0.35, blue: 0.4, alpha: 1)
            spire.lineWidth = 3
            spire.position = CGPoint(x: 0, y: 37)
            node.addChild(spire)
            let cap = SKShapeNode(ellipseOf: CGSize(width: 52, height: 20))
            cap.fillColor = SKColor(red: 0.42, green: 0.42, blue: 0.47, alpha: 1)
            cap.strokeColor = .clear
            cap.position = CGPoint(x: 0, y: 74)
            node.addChild(cap)
            let moss = SKShapeNode(ellipseOf: CGSize(width: 34, height: 12))
            moss.fillColor = SKColor(red: 0.35, green: 0.55, blue: 0.3, alpha: 0.9)
            moss.strokeColor = .clear
            moss.position = CGPoint(x: -8, y: 8)
            node.addChild(moss)
        case 2:
            let totem = SKShapeNode(rectOf: CGSize(width: 36, height: 76), cornerRadius: 6)
            totem.fillColor = SKColor(red: 0.5, green: 0.36, blue: 0.2, alpha: 1)
            totem.strokeColor = SKColor(red: 0.32, green: 0.22, blue: 0.12, alpha: 1)
            totem.lineWidth = 3
            totem.position = CGPoint(x: 0, y: 38)
            node.addChild(totem)
            for bandY in [24.0, 48.0] {
                let band = SKShapeNode(rectOf: CGSize(width: 36, height: 8))
                band.fillColor = SKColor(red: 0.3, green: 0.2, blue: 0.1, alpha: 1)
                band.strokeColor = .clear
                band.position = CGPoint(x: 0, y: CGFloat(bandY))
                node.addChild(band)
            }
            for (dx, rot) in [(-14.0, 0.6), (14.0, -0.6), (0.0, 0.0)] {
                let leaf = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12))
                leaf.fillColor = SKColor(red: 0.28, green: 0.55, blue: 0.28, alpha: 1)
                leaf.strokeColor = .clear
                leaf.zRotation = CGFloat(rot)
                leaf.position = CGPoint(x: CGFloat(dx), y: 80)
                node.addChild(leaf)
            }
        default:
            let conePath = CGMutablePath()
            conePath.move(to: CGPoint(x: -36, y: 0))
            conePath.addQuadCurve(to: CGPoint(x: 0, y: 76), control: CGPoint(x: -14, y: 44))
            conePath.addQuadCurve(to: CGPoint(x: 36, y: 0), control: CGPoint(x: 14, y: 44))
            conePath.closeSubpath()
            let cone = SKShapeNode(path: conePath)
            cone.fillColor = SKColor(red: 0.3, green: 0.24, blue: 0.24, alpha: 1)
            cone.strokeColor = SKColor(red: 0.18, green: 0.13, blue: 0.13, alpha: 1)
            cone.lineWidth = 3
            node.addChild(cone)
            let glow = SKShapeNode(circleOfRadius: 10)
            glow.fillColor = SKColor(red: 1.0, green: 0.5, blue: 0.15, alpha: 1)
            glow.strokeColor = .clear
            glow.glowWidth = 8
            glow.position = CGPoint(x: 0, y: 72)
            node.addChild(glow)
        }
        return node
    }

    private static func gradientTexture(size: CGSize, colors: [SKColor]) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            // Evenly spaced stops for however many colors are passed in -- this used to
            // hardcode `[0, 1]`, which silently produced no gradient at all (CGGradient's
            // initializer returns nil on a colors/locations count mismatch) the moment a third
            // sky color was added above.
            let locations: [CGFloat] = colors.count > 1
                ? (0..<colors.count).map { CGFloat($0) / CGFloat(colors.count - 1) }
                : [0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: locations
            ) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width / 2, y: 0),
                end: CGPoint(x: size.width / 2, y: size.height),
                options: []
            )
        }
        return SKTexture(image: image)
    }

    func deployPlayerUnit(unitIndex: Int, branchID: String? = nil, enhancementLevel: Int = 1) {
        guard !isGameOver, bundledUnits.indices.contains(unitIndex) else { return }
        let unit = bundledUnits[unitIndex]
        guard unit.deployCost <= amber else { return }
        guard lane.deploy(unit, activeBranchID: branchID, enhancementLevel: enhancementLevel, to: .player) else { return }
        amber -= unit.deployCost
        // Keep the fractional accumulator in sync with the spend, or next frame's re-derivation
        // of `amber` from the accumulator would silently undo this deduction.
        amberAccumulator = Double(amber)
    }

    /// Resets the battle to its starting state so the SwiftUI layer can offer "Play Again"
    /// instead of the game being stuck forever once someone wins or loses.
    func reset() {
        lane = Lane(length: 750, playerBaseHP: startingBaseHP, enemyBaseHP: startingBaseHP)
        amberAccumulator = 0
        amber = 0
        amberPerSecond = baseAmberPerSecond
        baseLevel = 1
        baseAttackUsed = false
        matchElapsedTime = 0
        enemyAmberAccumulator = 0
        enemySpawnCheckTimer = 0
        lastUpdateTime = nil
        isGameOver = false
        didPlayerWin = nil
        statusLabel.isHidden = true
        statusBacking.isHidden = true
        for visual in playerVisuals.values { visual.container.removeFromParent() }
        for visual in enemyVisuals.values { visual.container.removeFromParent() }
        playerVisuals.removeAll()
        enemyVisuals.removeAll()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let deltaTime = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime
        matchElapsedTime += deltaTime

        let amberMultiplier = isInDoubleAmberPhase ? 2.0 : 1.0
        lane.frontlineBUCap = isInDoubleAmberPhase ? Self.doubleAmberPhaseFrontlineBUCap : Lane.defaultFrontlineBUCap
        amberAccumulator += amberPerSecond * amberMultiplier * deltaTime
        let newAmber = Int(amberAccumulator)
        if newAmber != amber {
            amber = newAmber
        }

        enemyAmberAccumulator += enemyAmberPerSecond * amberMultiplier * deltaTime
        enemySpawnCheckTimer += deltaTime
        if enemySpawnCheckTimer >= enemySpawnCheckInterval {
            enemySpawnCheckTimer = 0
            let affordable = bundledUnits.filter {
                $0.deployCost <= enemyMaxUnitCost && Double($0.deployCost) <= enemyAmberAccumulator
            }
            if let pick = affordable.randomElement(), lane.deploy(pick, to: .enemy) {
                enemyAmberAccumulator -= Double(pick.deployCost)
            }
        }

        lane.tick(deltaTime: deltaTime)

        // The rendering flip in xPosition(for:) means player units visually march LEFT (toward
        // the enemy base on the left edge), so their facing flips with it.
        sync(units: lane.playerUnits, visuals: &playerVisuals, sideColor: .systemBlue, facesRight: false)
        sync(units: lane.enemyUnits, visuals: &enemyVisuals, sideColor: .systemRed, facesRight: true)
        updateLabels()
        checkGameOver()
        if !isGameOver, matchElapsedTime >= matchDurationSeconds {
            endGameByTimeLimit()
        }
    }

    private func sync(units: [DeployedUnit], visuals: inout [UUID: UnitVisual], sideColor: SKColor, facesRight: Bool) {
        var seenIDs = Set<UUID>()
        for unit in units {
            seenIDs.insert(unit.id)
            let visual: UnitVisual
            if let existing = visuals[unit.id] {
                visual = existing
            } else {
                visual = makeVisual(for: unit, sideColor: sideColor, facesRight: facesRight)
                visuals[unit.id] = visual
            }
            // Flying units render visibly higher up so "it's flying" is readable on screen, not
            // just a hidden stat -- there's no real art yet, so this is the only visual signal.
            let altitudeOffset: CGFloat = unit.effectiveStats.isFlying ? 40 : 0
            visual.container.position = CGPoint(x: xPosition(for: unit.position), y: size.height / 2 + altitudeOffset)
            visual.hpLabel.text = "\(max(0, unit.currentHP))"
        }
        for (id, visual) in visuals where !seenIDs.contains(id) {
            visual.container.removeFromParent()
            visuals.removeValue(forKey: id)
        }
    }

    /// Placeholder visuals only (real art is a later phase, per ART_BIBLE.md) -- but at least
    /// size now reflects BU class and the ring color reflects Era, so the two mechanics that
    /// actually differentiate units are visible on screen instead of every unit being an
    /// identical dot.
    private func makeVisual(for unit: DeployedUnit, sideColor: SKColor, facesRight: Bool) -> UnitVisual {
        let container = SKNode()
        let r = radius(for: unit.definition.sizeClass)
        // Each side faces its actual on-screen walk direction -- with the Battle Cats
        // orientation flip in xPosition(for:), player units face LEFT toward the enemy base.
        let facing: CGFloat = facesRight ? 1 : -1

        let shadow = SKShapeNode(ellipseOf: CGSize(width: r * 1.6, height: r * 0.5))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -r * 0.95)
        shadow.zPosition = -1
        container.addChild(shadow)

        // A rarity glow ring behind the body -- ties the battle-scene visuals to the Summons
        // rarity tiers (rollAndUnlock) so an SSR pull actually looks special on the field, not
        // just in the gacha result text.
        if let glowColor = rarityGlowColor(for: unit.definition.rarity) {
            let glow = SKShapeNode(circleOfRadius: r * 1.25)
            glow.fillColor = .clear
            glow.strokeColor = glowColor
            glow.lineWidth = unit.definition.rarity == .legendary ? 4 : 2.5
            glow.glowWidth = unit.definition.rarity == .legendary ? 5 : 2
            glow.alpha = unit.definition.rarity == .legendary ? 0.95 : 0.6
            glow.zPosition = -0.5
            container.addChild(glow)
        }

        // A soft translucent ring for ranged attackers and a pair of stylized wings for flying
        // ones -- the only visual cues those traits get without real illustrated art, so melee-
        // can't-hit-flying and ranged-only-attacks read as visibly different silhouettes.
        if unit.effectiveStats.isFlying {
            for side: CGFloat in [-1, 1] {
                let wing = SKShapeNode(ellipseOf: CGSize(width: r * 0.95, height: r * 0.4))
                wing.fillColor = SKColor.white.withAlphaComponent(0.55)
                wing.strokeColor = .clear
                wing.position = CGPoint(x: side * r * 0.85, y: r * 0.05)
                wing.zRotation = side * 0.45
                wing.zPosition = -0.3
                container.addChild(wing)
            }
        }
        if unit.effectiveStats.isRanged {
            let dashedRing = SKShapeNode(
                path: CGPath(
                    ellipseIn: CGRect(x: -r * 1.15, y: -r * 1.15, width: r * 2.3, height: r * 2.3),
                    transform: nil
                ).copy(dashingWithPhase: 0, lengths: [4, 3])
            )
            dashedRing.strokeColor = SKColor.white.withAlphaComponent(0.6)
            dashedRing.lineWidth = 1.5
            dashedRing.zPosition = -0.2
            container.addChild(dashedRing)
        }

        // A stubby tail poking out the back, drawn before the body so the body overlaps its
        // base -- the single cheapest silhouette change that makes a circle read "dinosaur."
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -r * 0.85 * facing, y: r * 0.2))
        tailPath.addQuadCurve(
            to: CGPoint(x: -r * 0.8 * facing, y: -r * 0.25),
            control: CGPoint(x: -r * 1.6 * facing, y: r * 0.35)
        )
        tailPath.closeSubpath()
        let tail = SKShapeNode(path: tailPath)
        tail.fillColor = sideColor
        tail.strokeColor = eraColor(for: unit.definition.era)
        tail.lineWidth = 2
        container.addChild(tail)

        let shape = SKShapeNode(circleOfRadius: r)
        shape.fillColor = sideColor
        shape.strokeColor = eraColor(for: unit.definition.era)
        shape.lineWidth = 3
        container.addChild(shape)

        // A soft highlight fakes the "chunky, rounded, toy-like" shading ART_BIBLE.md §1 calls
        // for, without needing real texture art.
        let highlight = SKShapeNode(ellipseOf: CGSize(width: r * 0.75, height: r * 0.45))
        highlight.fillColor = SKColor.white.withAlphaComponent(0.35)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -r * 0.3 * facing, y: r * 0.35)
        container.addChild(highlight)

        // Pale belly patch low on the front half -- the classic cartoon-dino two-tone.
        let belly = SKShapeNode(ellipseOf: CGSize(width: r * 0.95, height: r * 0.6))
        belly.fillColor = SKColor.white.withAlphaComponent(0.3)
        belly.strokeColor = .clear
        belly.position = CGPoint(x: r * 0.15 * facing, y: -r * 0.35)
        container.addChild(belly)

        // A snout bump on the leading edge so the body has a face direction even before the eye.
        let snout = SKShapeNode(ellipseOf: CGSize(width: r * 0.7, height: r * 0.5))
        snout.fillColor = sideColor
        snout.strokeColor = eraColor(for: unit.definition.era)
        snout.lineWidth = 2
        snout.position = CGPoint(x: r * 0.85 * facing, y: -r * 0.1)
        container.addChild(snout)

        // Two little feet nubs under the body.
        for footX in [-r * 0.35, r * 0.35] {
            let foot = SKShapeNode(ellipseOf: CGSize(width: r * 0.45, height: r * 0.28))
            foot.fillColor = SKColor.black.withAlphaComponent(0.3)
            foot.strokeColor = .clear
            foot.position = CGPoint(x: footX, y: -r * 0.9)
            container.addChild(foot)
        }

        // A single big forward-facing eye -- ART_BIBLE.md §2's "big eyes read as character"
        // rule, the cheapest possible way to make a placeholder circle look like a creature
        // instead of a token.
        let eyePosition = CGPoint(x: r * 0.4 * facing, y: r * 0.1)
        let eyeWhite = SKShapeNode(circleOfRadius: max(3, r * 0.32))
        eyeWhite.fillColor = .white
        eyeWhite.strokeColor = .black
        eyeWhite.lineWidth = 1
        eyeWhite.position = eyePosition
        container.addChild(eyeWhite)

        let pupil = SKShapeNode(circleOfRadius: max(1.2, r * 0.14))
        pupil.fillColor = .black
        pupil.strokeColor = .clear
        pupil.position = eyePosition
        container.addChild(pupil)

        let hpLabel = SKLabelNode(fontNamed: "Menlo")
        hpLabel.fontSize = 10
        hpLabel.fontColor = .white
        hpLabel.position = CGPoint(x: 0, y: r + 6)
        container.addChild(hpLabel)

        addChild(container)
        return UnitVisual(container: container, hpLabel: hpLabel)
    }

    private func radius(for sizeClass: SizeClass) -> CGFloat {
        switch sizeClass {
        case .tiny: return 10
        case .small: return 14
        case .medium: return 18
        case .large: return 24
        case .apex: return 32
        }
    }

    private func eraColor(for era: Era) -> SKColor {
        switch era {
        case .triassic: return .systemOrange
        case .jurassic: return .systemGreen
        case .cretaceous: return .systemTeal
        case .iceAge: return .white
        case .marine: return .systemBlue
        case .sky: return .systemPurple
        }
    }

    /// Common units get no glow at all -- it's meant to make rarer pulls stand out, not to
    /// decorate everything.
    private func rarityGlowColor(for rarity: Rarity) -> SKColor? {
        switch rarity {
        case .common: return nil
        case .rare: return .systemBlue
        case .epic: return .systemPurple
        case .legendary: return .systemYellow
        }
    }

    /// Battle Cats orientation: the player's base sits on the RIGHT edge and units march left
    /// toward the enemy base -- lane position 0 (the player's spawn) maps to the right side.
    /// This is purely a rendering flip; the simulation still runs 0 -> length internally.
    private func xPosition(for lanePosition: Double) -> CGFloat {
        let margin: CGFloat = 40
        let usableWidth = size.width - margin * 2
        let fraction = CGFloat(lanePosition / lane.length)
        return size.width - margin - usableWidth * fraction
    }

    private func updateLabels() {
        let multiplierTag = isInDoubleAmberPhase ? " (2x)" : ""
        amberLabel.text = "Amber \(amber)\(multiplierTag)"
        // Battle Cats-style "current/max" HP readouts floating above each base tower.
        playerBaseLabel.text = "\(max(0, lane.playerBaseHP))/\(startingBaseHP)"
        enemyBaseLabel.text = "\(max(0, lane.enemyBaseHP))/\(startingBaseHP)"
        let remaining = max(0, Int((matchDurationSeconds - matchElapsedTime).rounded(.up)))
        timeLabel.text = String(format: "Time: %d:%02d", remaining / 60, remaining % 60)

        let activeGroups: [SynergyGroup] = [.raptorPack, .armoredLine, .apexTitans].filter { group in
            lane.playerUnits.filter { $0.isAlive && $0.definition.synergyGroup == group }.count >= group.requiredCount
        }
        synergyLabel.text = activeGroups.isEmpty ? "" : "Synergy: " + activeGroups.map(\.displayName).joined(separator: ", ")
    }

    private func checkGameOver() {
        if lane.enemyBaseHP <= 0 {
            endGame(message: "YOU WIN", didWin: true)
        } else if lane.playerBaseHP <= 0 {
            endGame(message: "YOU LOSE", didWin: false)
        }
    }

    /// Neither base was destroyed within the 8-minute match clock -- whoever dealt more
    /// cumulative damage to the opposing base wins, same as the request's "most damage to the
    /// other's tower" rule. Base HP only ever decreases, so `startingBaseHP - remainingHP` is
    /// exactly the damage dealt, including any overkill past 0.
    private func endGameByTimeLimit() {
        let playerDamageDealt = startingBaseHP - lane.enemyBaseHP
        let enemyDamageDealt = startingBaseHP - lane.playerBaseHP
        if playerDamageDealt > enemyDamageDealt {
            endGame(message: "TIME UP — YOU WIN", didWin: true)
        } else if enemyDamageDealt > playerDamageDealt {
            endGame(message: "TIME UP — YOU LOSE", didWin: false)
        } else {
            endGame(message: "TIME UP — DRAW", didWin: nil)
        }
    }

    /// Set alongside `isGameOver` so the SwiftUI layer can grant a Fossil reward exactly once
    /// per match (see `BattleView`'s `onChange(of: scene.isGameOver)`) without re-deriving
    /// win/loss from the status text. `nil` covers the time-limit draw case.
    @Published private(set) var didPlayerWin: Bool?

    private func endGame(message: String, didWin: Bool?) {
        isGameOver = true
        didPlayerWin = didWin
        statusLabel.text = message
        statusLabel.isHidden = false
        statusBacking.isHidden = false
    }
}

// MARK: - Player persistence

/// The app's first real persistence -- everything else (a match's Amber, base HP, upgrades)
/// resets every time per `BattleScene.reset()`, but Fossils, which dinosaurs are unlocked, and
/// Enhance levels survive across app launches via `UserDefaults`.
final class PlayerProfile: ObservableObject {
    private static let fossilsKey = "roarfare.fossils"
    private static let eggsKey = "roarfare.eggs"
    private static let ownedKey = "roarfare.ownedUnitIDs"
    private static let levelsKey = "roarfare.unitLevels"
    private static let battlesWonKey = "roarfare.battlesWon"
    private static let achievementsKey = "roarfare.unlockedAchievements"
    private static let campaignKey = "roarfare.highestCampaignLevel"

    static let campaignLevelCount = 12

    static let startingFossils = 500
    static let startingEggs = 300
    // Matches RoarFareContentView.loadoutCap exactly, so the default owned set and the default
    // loadout line up on a fresh install -- nothing in the starting loadout is locked.
    static let startingOwnedCount = 10
    static let maxLevel = 10
    static let enhanceCostPerLevel = 80

    // Two currencies, gacha-style: Fossils pay for Enhance (permanent power on units you
    // already own, earned by just playing Campaign matches, win or lose); Eggs pay for Summons
    // (unlocking new units, earned only from PvP wins and Achievements). Keeping them separate
    // means grinding Campaign never buys you new roster slots, and vice versa.
    static let summonCost = 150
    static let tenSummonCost = summonCost * 10
    static let battleWinReward = 100
    static let battleLossReward = 30
    static let pvpWinEggReward = 5

    @Published var fossils: Int {
        didSet { UserDefaults.standard.set(fossils, forKey: Self.fossilsKey) }
    }
    @Published var eggs: Int {
        didSet { UserDefaults.standard.set(eggs, forKey: Self.eggsKey) }
    }
    @Published var ownedUnitIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(ownedUnitIDs), forKey: Self.ownedKey) }
    }
    @Published var unitLevels: [String: Int] {
        didSet { UserDefaults.standard.set(unitLevels, forKey: Self.levelsKey) }
    }
    @Published private(set) var battlesWon: Int {
        didSet { UserDefaults.standard.set(battlesWon, forKey: Self.battlesWonKey) }
    }
    @Published private(set) var unlockedAchievementIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(unlockedAchievementIDs), forKey: Self.achievementsKey) }
    }
    @Published private(set) var highestCampaignLevel: Int {
        didSet { UserDefaults.standard.set(highestCampaignLevel, forKey: Self.campaignKey) }
    }

    init() {
        let defaults = UserDefaults.standard
        fossils = defaults.object(forKey: Self.fossilsKey) != nil
            ? defaults.integer(forKey: Self.fossilsKey) : Self.startingFossils
        eggs = defaults.object(forKey: Self.eggsKey) != nil
            ? defaults.integer(forKey: Self.eggsKey) : Self.startingEggs
        if let savedOwned = defaults.array(forKey: Self.ownedKey) as? [String] {
            ownedUnitIDs = Set(savedOwned)
        } else {
            ownedUnitIDs = Set(bundledUnits.prefix(Self.startingOwnedCount).map(\.id))
        }
        unitLevels = defaults.dictionary(forKey: Self.levelsKey) as? [String: Int] ?? [:]
        battlesWon = defaults.integer(forKey: Self.battlesWonKey)
        // integer(forKey:) returns 0 when unset; stage 1 is always available.
        highestCampaignLevel = max(1, defaults.integer(forKey: Self.campaignKey))
        if let savedAchievements = defaults.array(forKey: Self.achievementsKey) as? [String] {
            unlockedAchievementIDs = Set(savedAchievements)
        } else {
            unlockedAchievementIDs = []
        }
    }

    var lockedUnitIDs: [String] {
        bundledUnits.map(\.id).filter { !ownedUnitIDs.contains($0) }
    }

    func level(for unitID: String) -> Int {
        unitLevels[unitID] ?? 1
    }

    func enhanceCost(for unitID: String) -> Int {
        Self.enhanceCostPerLevel * level(for: unitID)
    }

    @discardableResult
    func enhance(_ unitID: String) -> Bool {
        let currentLevel = level(for: unitID)
        guard currentLevel < Self.maxLevel else { return false }
        let cost = enhanceCost(for: unitID)
        guard fossils >= cost else { return false }
        fossils -= cost
        unitLevels[unitID] = currentLevel + 1
        checkAchievements()
        return true
    }

    enum SummonResult {
        case unlocked(UnitDefinition)
        case duplicateRefunded(Int)
        case notEnoughEggs
    }

    // Standard gacha-style weighted rarity odds -- common units are common, SSR (legendary) is
    // rare. The 10-pull uses slightly better odds per pull than 10 separate singles, the usual
    // "multi-pull sweetener" gacha games use to make bulk pulls feel worth doing.
    private static let singlePullOdds: [Rarity: Double] = [
        .common: 0.60, .rare: 0.27, .epic: 0.10, .legendary: 0.03
    ]
    private static let tenPullOdds: [Rarity: Double] = [
        .common: 0.55, .rare: 0.28, .epic: 0.12, .legendary: 0.05
    ]

    /// A single gacha pull: rolls a rarity tier by weighted odds, then picks a random still-locked
    /// unit of that tier. If every unit of the rolled tier is already owned, falls back to any
    /// other locked unit so a lucky SSR roll never just evaporates; if the whole roster is
    /// already owned, refunds half the spend in Eggs instead of wasting it.
    @discardableResult
    func summon() -> SummonResult {
        guard eggs >= Self.summonCost else { return .notEnoughEggs }
        eggs -= Self.summonCost
        let result = rollAndUnlock(odds: Self.singlePullOdds)
        checkAchievements()
        return result
    }

    /// A 10-pull at exactly 10x the single cost with slightly boosted SSR odds per pull (see
    /// `tenPullOdds`). Spends the full cost up front so a mid-roll "not enough Eggs" can't
    /// happen partway through.
    @discardableResult
    func summonTen() -> [SummonResult]? {
        guard eggs >= Self.tenSummonCost else { return nil }
        eggs -= Self.tenSummonCost
        let results = (0..<10).map { _ in rollAndUnlock(odds: Self.tenPullOdds) }
        checkAchievements()
        return results
    }

    private func rollAndUnlock(odds: [Rarity: Double]) -> SummonResult {
        let rolledRarity = Self.rollRarity(odds)
        let inTier = bundledUnits.filter { $0.rarity == rolledRarity && !ownedUnitIDs.contains($0.id) }
        if let pick = inTier.randomElement() {
            ownedUnitIDs.insert(pick.id)
            return .unlocked(pick)
        }
        let anyLocked = bundledUnits.filter { !ownedUnitIDs.contains($0.id) }
        if let pick = anyLocked.randomElement() {
            ownedUnitIDs.insert(pick.id)
            return .unlocked(pick)
        }
        let refund = Self.summonCost / 2
        eggs += refund
        return .duplicateRefunded(refund)
    }

    private static func rollRarity(_ odds: [Rarity: Double]) -> Rarity {
        let roll = Double.random(in: 0..<1)
        var cumulative = 0.0
        for rarity: Rarity in [.common, .rare, .epic, .legendary] {
            cumulative += odds[rarity] ?? 0
            if roll < cumulative { return rarity }
        }
        return .legendary
    }

    /// Later stages pay meaningfully better on a win (+15 Fossils per stage past the first), so
    /// replaying stage 1 forever is never the best farm once you can clear something harder.
    /// A loss pays the same small consolation everywhere.
    func rewardForMatch(didWin: Bool, campaignLevel: Int = 1) {
        if didWin { battlesWon += 1 }
        fossils += didWin
            ? Self.battleWinReward + (campaignLevel - 1) * 15
            : Self.battleLossReward
        checkAchievements()
    }

    /// Beating your current frontier stage unlocks the next one; replaying an earlier stage
    /// never moves the frontier backward (or forward -- you already earned past it).
    func unlockNextCampaignLevel(after level: Int) {
        guard level >= highestCampaignLevel, level < Self.campaignLevelCount else { return }
        highestCampaignLevel = level + 1
    }

    /// PvP has no real matchmaking backend yet (see `docs/ROADMAP.md` Phase 7), so
    /// `PvPStubView` calls this from a local "Simulate Battle" button instead of a real match
    /// result -- the currency reward is wired up and testable now, ready to hook to a real
    /// match outcome once matchmaking exists.
    func rewardForPvPWin() {
        eggs += Self.pvpWinEggReward
        checkAchievements()
    }

    private func checkAchievements() {
        for achievement in Achievement.all where !unlockedAchievementIDs.contains(achievement.id) {
            if achievement.isUnlocked(self) {
                unlockedAchievementIDs.insert(achievement.id)
                eggs += achievement.eggReward
            }
        }
    }
}

/// Milestone rewards paid in Eggs (the Summons currency) -- the second of the two ways to earn
/// Eggs besides PvP wins. Checked after every match, enhance, and summon so a milestone crossed
/// mid-action unlocks immediately instead of needing a separate "claim" step.
struct Achievement: Identifiable {
    let id: String
    let name: String
    let description: String
    let eggReward: Int
    let isUnlocked: (PlayerProfile) -> Bool

    static let all: [Achievement] = [
        Achievement(id: "first_win", name: "First Blood", description: "Win your first battle.", eggReward: 10) { $0.battlesWon >= 1 },
        Achievement(id: "ten_wins", name: "Veteran", description: "Win 10 battles.", eggReward: 25) { $0.battlesWon >= 10 },
        Achievement(id: "fifty_wins", name: "Champion", description: "Win 50 battles.", eggReward: 60) { $0.battlesWon >= 50 },
        Achievement(id: "collector_25", name: "Collector", description: "Own 25 dinosaurs.", eggReward: 20) { $0.ownedUnitIDs.count >= 25 },
        Achievement(id: "collector_50", name: "Curator", description: "Own 50 dinosaurs.", eggReward: 35) { $0.ownedUnitIDs.count >= 50 },
        Achievement(id: "full_roster", name: "Completionist", description: "Own every dinosaur.", eggReward: 75) { $0.ownedUnitIDs.count >= bundledUnits.count },
        Achievement(id: "enhancer_5", name: "Enhancer", description: "Enhance any dinosaur to level 5.", eggReward: 20) { profile in profile.unitLevels.values.contains { $0 >= 5 } },
        Achievement(id: "enhancer_max", name: "Perfectionist", description: "Enhance any dinosaur to max level.", eggReward: 40) { profile in profile.unitLevels.values.contains { $0 >= PlayerProfile.maxLevel } },
        Achievement(id: "campaign_6", name: "Trailblazer", description: "Reach Campaign Stage 6.", eggReward: 15) { $0.highestCampaignLevel >= 6 },
        Achievement(id: "campaign_12", name: "Apex of the Era", description: "Reach the final Campaign Stage.", eggReward: 50) { $0.highestCampaignLevel >= PlayerProfile.campaignLevelCount }
    ]
}

// MARK: - SwiftUI host view

/// The same sky-to-ground palette as `BattleScene.buildScenery()`, applied to every menu screen
/// so the whole app shares one look instead of the battle scene being the only screen that
/// isn't a plain white/black system background.
private let roarFareBackground = LinearGradient(
    colors: [
        Color(red: 0.96, green: 0.85, blue: 0.62),
        Color(red: 0.55, green: 0.72, blue: 0.52)
    ],
    startPoint: .top, endPoint: .bottom
)

private extension View {
    /// The app's one shared "big call-to-action" button look: gradient fill, bold white text,
    /// rounded corners, a light border, and a drop shadow. Replaces the flat
    /// `color.opacity(0.5)` flat-fill buttons every menu screen used before the graphics pass.
    func gameButtonStyle(color: Color, disabled: Bool = false) -> some View {
        self
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: disabled ? [Color.gray, Color.gray.opacity(0.7)] : [color, color.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
    }
}

/// Root view: owns the persistent `PlayerProfile` and the loadout, routing between the true
/// main menu and its sub-screens. Every trip into `.battle` gets a brand-new `BattleScene` (see
/// `BattleView`'s `@StateObject`), so leaving to the menu and battling again always starts a
/// clean match.
struct RoarFareContentView: View {
    private enum AppScreen {
        case mainMenu, campaignMenu, pvp, summons, enhance, achievements
        case battle(level: Int)
    }

    // Battle Cats-style loadout: you own the whole roster, but only bring `loadoutCap` units
    // into any one match -- forces a real pick each game instead of always having full access
    // to every unit, which is the actual point ("more variety in games"). Defaults to the
    // first 10 bundled units, matching `PlayerProfile.startingOwnedCount` exactly so nothing in
    // the starting loadout is locked.
    static let loadoutCap = 10
    @StateObject private var profile = PlayerProfile()
    @State private var loadout: Set<String> = Set(bundledUnits.prefix(loadoutCap).map(\.id))
    @State private var screen: AppScreen = .mainMenu

    var body: some View {
        switch screen {
        case .mainMenu:
            MainMenuView(
                profile: profile,
                onCampaign: { screen = .campaignMenu },
                onPvP: { screen = .pvp },
                onSummons: { screen = .summons },
                onEnhance: { screen = .enhance },
                onAchievements: { screen = .achievements }
            )
        case .campaignMenu:
            CampaignMenuView(
                profile: profile, loadout: $loadout,
                onBattle: { level in screen = .battle(level: level) },
                onHome: { screen = .mainMenu }
            )
        case .battle(let level):
            BattleView(profile: profile, loadout: loadout, level: level, onExit: { screen = .mainMenu })
        case .pvp:
            PvPStubView(profile: profile, onHome: { screen = .mainMenu })
        case .summons:
            SummonsView(profile: profile, onHome: { screen = .mainMenu })
        case .enhance:
            EnhanceView(profile: profile, onHome: { screen = .mainMenu })
        case .achievements:
            AchievementsView(profile: profile, onHome: { screen = .mainMenu })
        }
    }
}

/// The true home screen -- title, currency balances, and the five mode buttons (Clash
/// Royale/Battle Cats-style hub, "dinosaurs" per the brief). PvP is a stub for now: real
/// matchmaking needs a backend, which is explicitly Phase 7 in `docs/ROADMAP.md`, not something
/// a local single-player build can fake convincingly.
struct MainMenuView: View {
    @ObservedObject var profile: PlayerProfile
    let onCampaign: () -> Void
    let onPvP: () -> Void
    let onSummons: () -> Void
    let onEnhance: () -> Void
    let onAchievements: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Battle Cats "Cat Base" top bar: title on the left, currency counters pinned
            // top-right in their own chips.
            HStack(alignment: .firstTextBaseline) {
                Text("Dino Den")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.1))
                Spacer()
                currencyChip("🦴 \(profile.fossils)", tint: .orange)
                currencyChip("🥚 \(profile.eggs)", tint: .pink)
            }
            .padding(.top, 8)

            Spacer()

            Text("RoarFare")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.3, green: 0.2, blue: 0.08))
                .shadow(color: .white.opacity(0.6), radius: 0, x: 0, y: 2)
            Text("A Dinosaur Lane Battler")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            menuButton("🦖 CAMPAIGN", color: .green, action: onCampaign)
            menuButton("⚔️ PVP", color: .blue, action: onPvP)
            menuButton("🥚 SUMMONS", color: .purple, action: onSummons)
            menuButton("⚡ ENHANCE", color: .orange, action: onEnhance)
            menuButton("🏆 ACHIEVEMENTS", color: .yellow, action: onAchievements)

            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(roarFareBackground.ignoresSafeArea())
    }

    private func currencyChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundColor(tint)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.55))
            .cornerRadius(12)
    }

    private func menuButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .gameButtonStyle(color: color)
    }
}

/// Stage-select screen: 12 campaign stages in a grid, unlocked one at a time by beating the
/// previous one (Battle Cats chapter-map style, minus the world map art for now). Each stage is
/// a real difficulty step -- the enemy earns Amber faster and can afford bigger dinosaurs -- and
/// gets its own enemy base design in the battle scene.
struct CampaignMenuView: View {
    @ObservedObject var profile: PlayerProfile
    @Binding var loadout: Set<String>
    let onBattle: (Int) -> Void
    let onHome: () -> Void
    @State private var showingLoadoutEditor = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("← Home") { onHome() }
                Spacer()
                Text("🦴 \(profile.fossils)").foregroundColor(.orange).font(.subheadline.bold())
            }
            .padding(.horizontal)

            Text("Campaign").font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("Beat a stage to unlock the next. Tougher rivals, bigger rewards.")
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(1...PlayerProfile.campaignLevelCount, id: \.self) { level in
                    let unlocked = level <= profile.highestCampaignLevel
                    Button {
                        onBattle(level)
                    } label: {
                        VStack(spacing: 3) {
                            Text(unlocked ? "🦖" : "🔒").font(.title3)
                            Text("Stage \(level)").font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: unlocked
                                    ? [Color.green, Color.green.opacity(0.65)]
                                    : [Color.gray.opacity(0.6), Color.gray.opacity(0.4)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    }
                    .foregroundColor(.white)
                    .disabled(!unlocked || loadout.isEmpty)
                }
            }
            .padding(.horizontal, 20)

            Button("Edit Loadout (\(loadout.count)/\(RoarFareContentView.loadoutCap))") {
                showingLoadoutEditor = true
            }
            .font(.subheadline.bold())
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 22)
            .background(
                LinearGradient(colors: [Color.purple, Color.purple.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            )
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)

            if loadout.isEmpty {
                Text("Equip at least one dinosaur to battle.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(roarFareBackground.ignoresSafeArea())
        .sheet(isPresented: $showingLoadoutEditor) {
            LoadoutEditorView(loadout: $loadout, ownedUnitIDs: profile.ownedUnitIDs)
        }
    }
}

/// The actual match screen, laid out Battle Cats-style: the scene up top (bases at each end,
/// HP over each tower), and the 10 equipped dinosaurs as tap-to-deploy cards sitting on a brown
/// "dirt band" at the bottom, two rows of five. One card per equipped unit -- which form it
/// deploys as (base or an evolution) is decided automatically by its Enhance level via
/// `autoEvolutionBranchID`, the way Battle Cats evolves units at level milestones, instead of
/// the old wall of one-button-per-branch. Takes `loadout` as a plain value on purpose: the
/// loadout you brought into a battle shouldn't change mid-fight.
struct BattleView: View {
    @ObservedObject var profile: PlayerProfile
    let loadout: Set<String>
    let level: Int
    let onExit: () -> Void

    @StateObject private var scene: BattleScene

    init(profile: PlayerProfile, loadout: Set<String>, level: Int, onExit: @escaping () -> Void) {
        self.profile = profile
        self.loadout = loadout
        self.level = level
        self.onExit = onExit
        // StateObject's autoclosure runs exactly once per BattleView identity, so the stage
        // number is baked into the scene before SpriteKit ever presents it.
        _scene = StateObject(wrappedValue: {
            let scene = BattleScene(size: CGSize(width: 400, height: 300))
            scene.scaleMode = .resizeFill
            scene.campaignLevel = level
            return scene
        }())
    }

    private var equippedUnits: [(index: Int, unit: UnitDefinition)] {
        bundledUnits.enumerated()
            .filter { loadout.contains($0.element.id) }
            .map { (index: $0.offset, unit: $0.element) }
    }

    private let cardColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)
    private let dirtBrown = Color(red: 0.45, green: 0.32, blue: 0.18)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Home") { onExit() }
                    .padding(8)
                Spacer()
                Text("Stage \(level)").font(.subheadline.bold()).padding(.trailing, 12)
            }

            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The Battle Cats bottom band: match controls on one row, unit cards below, all on
            // dirt brown so the scene's ground visually continues into the HUD.
            VStack(spacing: 8) {
                if scene.isGameOver {
                    HStack(spacing: 10) {
                        Button("Play Again") { scene.reset() }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 18)
                            .background(Color.green.opacity(0.85))
                            .cornerRadius(10)

                        Button("Home") { onExit() }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 18)
                            .background(Color.gray.opacity(0.85))
                            .cornerRadius(10)
                    }
                } else {
                    let upgradeAffordable = scene.baseUpgradeCost <= scene.amber
                    HStack(spacing: 10) {
                        Button("⛏ Base Lv\(scene.baseLevel) · \(scene.baseUpgradeCost)") {
                            scene.upgradeBase()
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background((upgradeAffordable ? Color.orange : Color.gray).opacity(0.9))
                        .cornerRadius(10)
                        .disabled(!upgradeAffordable)

                        Spacer()

                        Button(scene.baseAttackUsed ? "💥 Used" : "💥 Bone Cannon") {
                            scene.fireBaseAttack()
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background((scene.baseAttackUsed ? Color.gray : Color.red).opacity(0.9))
                        .cornerRadius(10)
                        .disabled(scene.baseAttackUsed)
                    }
                }

                LazyVGrid(columns: cardColumns, spacing: 6) {
                    ForEach(equippedUnits, id: \.unit.id) { entry in
                        deployCard(for: entry.unit, atIndex: entry.index)
                    }
                }
            }
            .padding(10)
            .background(dirtBrown)
        }
        .onChange(of: scene.isGameOver) { isOver in
            guard isOver else { return }
            let won = scene.didPlayerWin == true
            profile.rewardForMatch(didWin: won, campaignLevel: level)
            if won { profile.unlockNextCampaignLevel(after: level) }
        }
    }

    private func deployCard(for unit: UnitDefinition, atIndex index: Int) -> some View {
        let enhanceLevel = profile.level(for: unit.id)
        let branchID = autoEvolutionBranchID(for: unit, enhancementLevel: enhanceLevel)
        let affordable = unit.deployCost <= scene.amber && !scene.isGameOver

        return Button {
            scene.deployPlayerUnit(unitIndex: index, branchID: branchID, enhancementLevel: enhanceLevel)
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    Circle()
                        .fill(eraCardColor(for: unit.era))
                        .frame(width: 26, height: 26)
                    Circle().fill(Color.white).frame(width: 8, height: 8).offset(x: 5, y: -3)
                    Circle().fill(Color.black).frame(width: 4, height: 4).offset(x: 5, y: -3)
                }
                Text(unit.name)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundColor(affordable ? .black : .white.opacity(0.7))
                Text("\(unit.deployCost)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(affordable ? Color(red: 0.75, green: 0.5, blue: 0.05) : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(affordable ? Color(red: 0.97, green: 0.93, blue: 0.8) : Color.black.opacity(0.35))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(rarityCardColor(for: unit.rarity), lineWidth: unit.rarity == .legendary ? 2 : 1.2)
            )
            .overlay(alignment: .topTrailing) {
                if branchID != nil {
                    Text("✦")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .padding(2)
                }
            }
            .overlay(alignment: .topLeading) {
                if enhanceLevel > 1 {
                    Text("Lv\(enhanceLevel)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(4)
                        .padding(2)
                }
            }
        }
        .disabled(!affordable)
    }
}

/// SwiftUI-side mirrors of the scene's era/rarity color language, so the deploy cards speak the
/// same visual dialect as the units they spawn.
private func eraCardColor(for era: Era) -> Color {
    switch era {
    case .triassic: return .orange
    case .jurassic: return .green
    case .cretaceous: return .teal
    case .iceAge: return Color(white: 0.9)
    case .marine: return .blue
    case .sky: return .purple
    }
}

private func rarityCardColor(for rarity: Rarity) -> Color {
    switch rarity {
    case .common: return Color.black.opacity(0.25)
    case .rare: return .blue
    case .epic: return .purple
    case .legendary: return .yellow
    }
}

/// Toggle up to `RoarFareContentView.loadoutCap` units in/out of the loadout. Locked units (not
/// yet unlocked via Summons) show a 🔒 and can't be selected at all. Once the cap is hit,
/// unselected-but-owned rows disable themselves rather than silently no-op'ing on tap, so it's
/// clear *why* nothing happened when you try to add an 11th unit.
struct LoadoutEditorView: View {
    @Binding var loadout: Set<String>
    let ownedUnitIDs: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(bundledUnits) { unit in
                let owned = ownedUnitIDs.contains(unit.id)
                let isSelected = loadout.contains(unit.id)
                let atCap = loadout.count >= RoarFareContentView.loadoutCap
                Button {
                    guard owned else { return }
                    if isSelected {
                        loadout.remove(unit.id)
                    } else if !atCap {
                        loadout.insert(unit.id)
                    }
                } label: {
                    HStack {
                        Text(unit.name)
                        if !owned {
                            Text("🔒").font(.caption)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                }
                .disabled(!owned || (!isSelected && atCap))
                .foregroundColor(!owned ? .gray : (isSelected ? .primary : (atCap ? .gray : .primary)))
            }
            .navigationTitle("Loadout (\(loadout.count)/\(RoarFareContentView.loadoutCap))")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The gacha screen -- spend Eggs for a chance at any locked dinosaur, weighted by rarity (see
/// `PlayerProfile.singlePullOdds`/`tenPullOdds`). A single pull or a 10-pull with slightly
/// better SSR odds, matching the standard mobile-gacha "multi-pull sweetener" pattern.
struct SummonsView: View {
    @ObservedObject var profile: PlayerProfile
    let onHome: () -> Void
    @State private var lastResults: [PlayerProfile.SummonResult] = []

    private func rarityEmoji(_ rarity: Rarity) -> String {
        switch rarity {
        case .common: return "⚪️"
        case .rare: return "🔵"
        case .epic: return "🟣"
        case .legendary: return "🌟"
        }
    }

    private func describe(_ result: PlayerProfile.SummonResult) -> String {
        switch result {
        case .unlocked(let unit):
            return "\(rarityEmoji(unit.rarity)) \(unit.name) — \(unit.rarity.displayName)"
        case .duplicateRefunded(let amount):
            return "Everything owned — refunded \(amount) 🥚"
        case .notEnoughEggs:
            return "Not enough Eggs."
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("← Home") { onHome() }
                Spacer()
            }
            .padding(.horizontal)

            Text("Summons").font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("🥚 \(profile.eggs) Eggs").foregroundColor(.pink)
            Text("\(profile.lockedUnitIDs.count) of \(bundledUnits.count) dinosaurs still locked")
                .font(.caption)
                .foregroundColor(.secondary)

            if !lastResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lastResults.enumerated()), id: \.offset) { _, result in
                            Text(describe(result)).font(.subheadline)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .background(Color.white.opacity(0.6))
                .cornerRadius(10)
                .padding(.horizontal, 30)
            }

            let singleAffordable = profile.eggs >= PlayerProfile.summonCost
            Button("Summon x1 (\(PlayerProfile.summonCost) 🥚)") {
                lastResults = [profile.summon()]
            }
            .gameButtonStyle(color: .purple, disabled: !singleAffordable)
            .disabled(!singleAffordable)
            .padding(.horizontal, 40)

            let tenAffordable = profile.eggs >= PlayerProfile.tenSummonCost
            Button {
                if let results = profile.summonTen() {
                    lastResults = results
                } else {
                    lastResults = [.notEnoughEggs]
                }
            } label: {
                VStack(spacing: 2) {
                    Text("Summon x10 (\(PlayerProfile.tenSummonCost) 🥚)")
                    Text("Better SSR odds").font(.caption)
                }
            }
            .gameButtonStyle(color: .indigo, disabled: !tenAffordable)
            .disabled(!tenAffordable)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(roarFareBackground.ignoresSafeArea())
    }
}

/// Spend Fossils to permanently level up an owned unit (+5% attackDamage/maxHP per level, see
/// `DeployedUnit.effectiveStats`, capped at `PlayerProfile.maxLevel`). Only shows owned units --
/// nothing to enhance until Summons unlocks it.
struct EnhanceView: View {
    @ObservedObject var profile: PlayerProfile
    let onHome: () -> Void

    private var ownedUnits: [UnitDefinition] {
        bundledUnits.filter { profile.ownedUnitIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Home") { onHome() }
                Spacer()
                Text("🦴 \(profile.fossils)").foregroundColor(.orange)
            }
            .padding()

            Text("Enhance")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .padding(.bottom, 8)

            List(ownedUnits) { unit in
                let level = profile.level(for: unit.id)
                let maxed = level >= PlayerProfile.maxLevel
                let cost = profile.enhanceCost(for: unit.id)
                let affordable = profile.fossils >= cost

                HStack {
                    VStack(alignment: .leading) {
                        Text(unit.name)
                        Text(maxed ? "Level \(level) (MAX)" : "Level \(level) → \(level + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !maxed {
                        Button("+\(cost) 🦴") {
                            profile.enhance(unit.id)
                        }
                        .disabled(!affordable)
                        .foregroundColor(affordable ? .primary : .gray)
                    }
                }
                .listRowBackground(Color.white.opacity(0.6))
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(roarFareBackground.ignoresSafeArea())
    }
}

/// Real matchmaking and a live opponent need a backend this local single-player build doesn't
/// have (see `docs/ROADMAP.md` Phase 7, "Rival Grounds"), but the Egg reward that a PvP win is
/// supposed to grant (`PlayerProfile.rewardForPvPWin`) is real -- this "Simulate" button lets
/// that reward loop actually be tested now instead of sitting dead code until a backend exists.
struct PvPStubView: View {
    @ObservedObject var profile: PlayerProfile
    let onHome: () -> Void
    @State private var lastResultMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("← Home") { onHome() }
                Spacer()
                Text("🥚 \(profile.eggs)").foregroundColor(.pink)
            }
            .padding(.horizontal)

            Spacer()
            Text("PvP").font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("Rival Grounds is planned but needs a real backend for matchmaking and live opponents — see docs/ROADMAP.md Phase 7. Simulate a quick skirmish below to test the reward loop in the meantime.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 30)

            if let message = lastResultMessage {
                Text(message)
                    .font(.headline)
                    .padding()
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(10)
            }

            Button("⚔️ Simulate PvP Battle") {
                if Bool.random() {
                    profile.rewardForPvPWin()
                    lastResultMessage = "Victory! +\(PlayerProfile.pvpWinEggReward) 🥚"
                } else {
                    lastResultMessage = "Defeat. No reward this time."
                }
            }
            .gameButtonStyle(color: .blue)
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(roarFareBackground.ignoresSafeArea())
    }
}

/// Milestone list -- see `Achievement.all` for the actual conditions/rewards. Reachable from the
/// Main Menu; unlocked items show a checkmark, locked ones show what they still need.
struct AchievementsView: View {
    @ObservedObject var profile: PlayerProfile
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("← Home") { onHome() }
                Spacer()
                Text("🥚 \(profile.eggs)").foregroundColor(.pink)
            }
            .padding()

            Text("Achievements")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .padding(.bottom, 8)

            List(Achievement.all) { achievement in
                let unlocked = profile.unlockedAchievementIDs.contains(achievement.id)
                HStack {
                    Image(systemName: unlocked ? "checkmark.seal.fill" : "lock.fill")
                        .foregroundColor(unlocked ? .green : .gray)
                    VStack(alignment: .leading) {
                        Text(achievement.name).font(.headline)
                        Text(achievement.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("🥚\(achievement.eggReward)")
                        .foregroundColor(unlocked ? .secondary : .pink)
                }
                .listRowBackground(Color.white.opacity(0.6))
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(roarFareBackground.ignoresSafeArea())
    }
}
