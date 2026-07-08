import Foundation
import SpriteKit
import SwiftUI
import Combine

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
}

enum Rarity {
    case common, rare, epic, legendary
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

    func applying(_ modifiers: StatModifiers) -> UnitStats {
        UnitStats(
            maxHP: maxHP + modifiers.maxHP,
            attackDamage: attackDamage + modifiers.attackDamage,
            attackIntervalSeconds: attackIntervalSeconds + modifiers.attackIntervalSeconds,
            rangeUnits: rangeUnits,
            knockbackResistant: knockbackResistant || modifiers.grantsKnockbackResistance,
            dealsKnockback: dealsKnockback || modifiers.grantsKnockbackAttack
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

struct UnitDefinition: Identifiable {
    let id: String
    let name: String
    let era: Era
    let sizeClass: SizeClass
    let rarity: Rarity
    let deployCost: Int
    let baseStats: UnitStats
    let evolutionBranches: [EvolutionBranch]

    init(
        id: String, name: String, era: Era, sizeClass: SizeClass, rarity: Rarity,
        deployCost: Int, baseStats: UnitStats, evolutionBranches: [EvolutionBranch] = []
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
    var currentHP: Int
    var position: Double
    var attackCooldownRemaining: Double = 0
    var hasUsedFirstStrike: Bool = false

    init(definition: UnitDefinition, activeBranchID: String? = nil, position: Double) {
        self.definition = definition
        self.activeBranchID = activeBranchID
        self.position = position
        self.currentHP = Self.effectiveStats(definition: definition, activeBranchID: activeBranchID).maxHP
    }

    var blockingUnits: Int { definition.sizeClass.blockingUnits }
    var isAlive: Bool { currentHP > 0 }
    var effectiveStats: UnitStats { Self.effectiveStats(definition: definition, activeBranchID: activeBranchID) }

    var activeAbility: Ability? {
        guard let branchID = activeBranchID else { return nil }
        return definition.branch(withID: branchID)?.ability
    }

    private static func effectiveStats(definition: UnitDefinition, activeBranchID: String?) -> UnitStats {
        guard let branchID = activeBranchID, let branch = definition.branch(withID: branchID) else {
            return definition.baseStats
        }
        return definition.baseStats.applying(branch.statModifiers)
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
    static let frontlineBUCap = 10
    static let tinyUnitHeadcountCap = 6
    static let knockbackDistance = 3.0
    static let frontlineEngagementRange = 2.0

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
        max(0, Self.frontlineBUCap - currentBU(for: side))
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
    func deploy(_ definition: UnitDefinition, activeBranchID: String? = nil, to side: Side) -> Bool {
        guard currentBU(for: side) + definition.sizeClass.blockingUnits <= Self.frontlineBUCap else {
            return false
        }
        if definition.sizeClass == .tiny, tinyUnitCount(for: side) >= Self.tinyUnitHeadcountCap {
            return false
        }
        let startPosition = side == .player ? 0 : length
        let unit = DeployedUnit(definition: definition, activeBranchID: activeBranchID, position: startPosition)
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

    func tick(deltaTime: Double, walkSpeed: Double = 5.0) {
        resolveCombatAndMovement(
            attackers: &playerUnits, defenders: &enemyUnits,
            advancesTowardIncreasingPosition: true, defendersBaseHP: &enemyBaseHP,
            deltaTime: deltaTime, walkSpeed: walkSpeed
        )
        resolveCombatAndMovement(
            attackers: &enemyUnits, defenders: &playerUnits,
            advancesTowardIncreasingPosition: false, defendersBaseHP: &playerBaseHP,
            deltaTime: deltaTime, walkSpeed: walkSpeed
        )
        clearDefeatedUnits()
    }

    private func resolveCombatAndMovement(
        attackers: inout [DeployedUnit], defenders: inout [DeployedUnit],
        advancesTowardIncreasingPosition: Bool, defendersBaseHP: inout Int,
        deltaTime: Double, walkSpeed: Double
    ) {
        for i in attackers.indices {
            guard attackers[i].isAlive else { continue }
            var stats = attackers[i].effectiveStats
            stats.attackIntervalSeconds *= Self.auraAttackIntervalMultiplier(for: attackers[i], allies: attackers)

            if attackers[i].attackCooldownRemaining > 0 {
                attackers[i].attackCooldownRemaining -= deltaTime
            }

            if let targetIndex = Self.nearestAliveDefenderInRange(
                from: attackers[i].position, range: stats.rangeUnits, defenders: defenders
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
                let delta = (advancesTowardIncreasingPosition ? 1.0 : -1.0) * walkSpeed * deltaTime
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

    private static func nearestAliveDefenderInRange(from position: Double, range: Double, defenders: [DeployedUnit]) -> Int? {
        var bestIndex: Int?
        var bestDistance = Double.infinity
        for (index, defender) in defenders.enumerated() {
            guard defender.isAlive else { continue }
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
        ]
    ),
    UnitDefinition(
        id: "deinonychus", name: "Deinonychus", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 320, baseStats: UnitStats(maxHP: 130, attackDamage: 32, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "pack_leader", name: "Pack Leader", statModifiers: StatModifiers(), abilityDescription: "Pack Hunting bonus with other raptors."),
            EvolutionBranch(id: "ambush_striker", name: "Ambush Striker", statModifiers: StatModifiers(maxHP: -10), abilityDescription: "First hit deals 3x damage.", ability: .firstHitBonus(damageMultiplier: 3.0))
        ]
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
        ]
    ),
    UnitDefinition(
        id: "stegosaurus", name: "Stegosaurus", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 750, baseStats: UnitStats(maxHP: 700, attackDamage: 55, attackIntervalSeconds: 1.6, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "thagomizer_guardian", name: "Thagomizer Guardian", statModifiers: StatModifiers(attackDamage: 15, grantsKnockbackAttack: true), abilityDescription: "Tail-spike swing knocks enemies back.")
        ]
    ),
    UnitDefinition(
        id: "ankylosaurus", name: "Ankylosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 800, baseStats: UnitStats(maxHP: 780, attackDamage: 48, attackIntervalSeconds: 1.4, rangeUnits: 1.2, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "club_tail_breaker", name: "Club-Tail Breaker", statModifiers: StatModifiers(attackDamage: 20, grantsKnockbackAttack: true), abilityDescription: "Heavier tail-club hits knock enemies back.")
        ]
    ),
    UnitDefinition(
        id: "tyrannosaurus_rex", name: "Tyrannosaurus Rex", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1800, baseStats: UnitStats(maxHP: 1600, attackDamage: 220, attackIntervalSeconds: 2.2, rangeUnits: 1.0, knockbackResistant: true),
        // SSR-tier: two evolutions, per the current art/roster pass.
        evolutionBranches: [
            EvolutionBranch(id: "tyrant_king", name: "Tyrant King", statModifiers: StatModifiers(maxHP: 200, attackDamage: 40), abilityDescription: "Pure apex-predator scaling: more HP, more damage."),
            EvolutionBranch(id: "bone_crusher", name: "Bone-Crusher", statModifiers: StatModifiers(attackDamage: 80, attackIntervalSeconds: 0.3, grantsKnockbackAttack: true), abilityDescription: "Slower but devastating bite that knocks enemies back.")
        ]
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
        deployCost: 310, baseStats: UnitStats(maxHP: 125, attackDamage: 34, attackIntervalSeconds: 0.9, rangeUnits: 1.2),
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
        ]
    ),
    UnitDefinition(
        id: "utahraptor", name: "Utahraptor", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 330, baseStats: UnitStats(maxHP: 140, attackDamage: 34, attackIntervalSeconds: 0.9, rangeUnits: 1.0),
        evolutionBranches: [
            EvolutionBranch(id: "slash_hunter", name: "Slash Hunter", statModifiers: StatModifiers(attackDamage: 12), abilityDescription: "Bigger sickle-claw damage.")
        ]
    ),
    UnitDefinition(
        id: "styracosaurus", name: "Styracosaurus", era: .cretaceous, sizeClass: .medium, rarity: .rare,
        deployCost: 520, baseStats: UnitStats(maxHP: 440, attackDamage: 36, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "spike_crown", name: "Spike Crown", statModifiers: StatModifiers(maxHP: 60, grantsKnockbackResistance: true), abilityDescription: "Reinforced frill, even harder to knock back.")
        ]
    ),
    UnitDefinition(
        id: "pentaceratops", name: "Pentaceratops", era: .cretaceous, sizeClass: .medium, rarity: .epic,
        deployCost: 600, baseStats: UnitStats(maxHP: 500, attackDamage: 38, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true),
        evolutionBranches: [
            EvolutionBranch(id: "five_horn_vanguard", name: "Five-Horn Vanguard", statModifiers: StatModifiers(maxHP: 80, attackDamage: 10), abilityDescription: "All five horns reinforced -- tougher and stronger.")
        ]
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
        ]
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
    )
]

/// One tappable deploy button: a unit's base form, or one of its evolution branches.
/// Branches deploy at the same Amber cost as the base form in this prototype -- the real
/// design (GAME_DESIGN.md §5) evolves permanently using Evolution Catalysts, not a per-deploy
/// currency choice; this is a simplification specific to this playable slice.
struct DeployOption: Identifiable {
    let id: String
    let label: String
    let unitIndex: Int
    let branchID: String?
    let cost: Int
    let era: Era
}

let deployOptions: [DeployOption] = {
    var options: [DeployOption] = []
    for (index, unit) in bundledUnits.enumerated() {
        options.append(DeployOption(id: unit.id, label: unit.name, unitIndex: index, branchID: nil, cost: unit.deployCost, era: unit.era))
        for branch in unit.evolutionBranches {
            options.append(DeployOption(
                id: "\(unit.id)_\(branch.id)",
                label: "\(unit.name) (\(branch.name))",
                unitIndex: index,
                branchID: branch.id,
                cost: unit.deployCost,
                era: unit.era
            ))
        }
    }
    return options
}()

/// The only Eras with any bundled units right now (see `GAME_DESIGN.md` §11 MVP scope) --
/// iceAge/marine/sky are real `Era` cases but have no roster content yet, so they're
/// deliberately left out of the deploy-tab list rather than showing an always-empty tab.
let populatedEras: [Era] = [.triassic, .jurassic, .cretaceous]

// MARK: - SpriteKit battle scene

final class BattleScene: SKScene, ObservableObject {
    private var lane = Lane(length: 900, playerBaseHP: 1000, enemyBaseHP: 1000)
    private var lastUpdateTime: TimeInterval?

    // Amber is tracked as a whole number (it was only ever displayed as Int anyway) and
    // @Published is only updated when that whole number actually changes -- publishing every
    // frame at 60fps just to grey out buttons would be wasteful and can visibly stutter SwiftUI.
    private var amberAccumulator: Double = 0
    @Published private(set) var amber: Int = 0
    // Was 20/sec, dropped to 12/sec after the first playtest (20 was too fast), then dropped
    // further to 8/sec -- that turned out too slow, so back to 12/sec.
    private let amberPerSecond: Double = 12

    // The enemy has its own economy now, gated the same way the player's is -- previously this
    // spawned a uniformly random unit (including the 1800-cost T. Rex) every 2 seconds with no
    // cost check at all, which made the game unwinnable regardless of player skill. Now it can
    // only deploy what it can actually afford, accruing slightly slower than the player.
    private var enemyAmberAccumulator: Double = 0
    private let enemyAmberPerSecond: Double = 10
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
    private let playerBaseLabel = SKLabelNode(fontNamed: "Menlo")
    private let enemyBaseLabel = SKLabelNode(fontNamed: "Menlo")
    private let statusLabel = SKLabelNode(fontNamed: "Menlo")

    override func didMove(to view: SKView) {
        backgroundColor = .black

        amberLabel.fontSize = 18
        amberLabel.horizontalAlignmentMode = .left
        amberLabel.position = CGPoint(x: 20, y: size.height - 30)
        addChild(amberLabel)

        playerBaseLabel.fontSize = 18
        playerBaseLabel.horizontalAlignmentMode = .left
        playerBaseLabel.position = CGPoint(x: 20, y: size.height - 55)
        addChild(playerBaseLabel)

        enemyBaseLabel.fontSize = 18
        enemyBaseLabel.horizontalAlignmentMode = .right
        enemyBaseLabel.position = CGPoint(x: size.width - 20, y: size.height - 55)
        addChild(enemyBaseLabel)

        statusLabel.fontSize = 32
        statusLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        statusLabel.isHidden = true
        addChild(statusLabel)
    }

    func deployPlayerUnit(unitIndex: Int, branchID: String? = nil) {
        guard !isGameOver, bundledUnits.indices.contains(unitIndex) else { return }
        let unit = bundledUnits[unitIndex]
        guard unit.deployCost <= amber else { return }
        guard lane.deploy(unit, activeBranchID: branchID, to: .player) else { return }
        amber -= unit.deployCost
        // Keep the fractional accumulator in sync with the spend, or next frame's re-derivation
        // of `amber` from the accumulator would silently undo this deduction.
        amberAccumulator = Double(amber)
    }

    /// Resets the battle to its starting state so the SwiftUI layer can offer "Play Again"
    /// instead of the game being stuck forever once someone wins or loses.
    func reset() {
        lane = Lane(length: 900, playerBaseHP: 1000, enemyBaseHP: 1000)
        amberAccumulator = 0
        amber = 0
        enemyAmberAccumulator = 0
        enemySpawnCheckTimer = 0
        lastUpdateTime = nil
        isGameOver = false
        statusLabel.isHidden = true
        for visual in playerVisuals.values { visual.container.removeFromParent() }
        for visual in enemyVisuals.values { visual.container.removeFromParent() }
        playerVisuals.removeAll()
        enemyVisuals.removeAll()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let deltaTime = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime

        amberAccumulator += amberPerSecond * deltaTime
        let newAmber = Int(amberAccumulator)
        if newAmber != amber {
            amber = newAmber
        }

        enemyAmberAccumulator += enemyAmberPerSecond * deltaTime
        enemySpawnCheckTimer += deltaTime
        if enemySpawnCheckTimer >= enemySpawnCheckInterval {
            enemySpawnCheckTimer = 0
            let affordable = bundledUnits.filter { Double($0.deployCost) <= enemyAmberAccumulator }
            if let pick = affordable.randomElement(), lane.deploy(pick, to: .enemy) {
                enemyAmberAccumulator -= Double(pick.deployCost)
            }
        }

        lane.tick(deltaTime: deltaTime)

        sync(units: lane.playerUnits, visuals: &playerVisuals, sideColor: .systemBlue)
        sync(units: lane.enemyUnits, visuals: &enemyVisuals, sideColor: .systemRed)
        updateLabels()
        checkGameOver()
    }

    private func sync(units: [DeployedUnit], visuals: inout [UUID: UnitVisual], sideColor: SKColor) {
        var seenIDs = Set<UUID>()
        for unit in units {
            seenIDs.insert(unit.id)
            let visual: UnitVisual
            if let existing = visuals[unit.id] {
                visual = existing
            } else {
                visual = makeVisual(for: unit, sideColor: sideColor)
                visuals[unit.id] = visual
            }
            visual.container.position = CGPoint(x: xPosition(for: unit.position), y: size.height / 2)
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
    private func makeVisual(for unit: DeployedUnit, sideColor: SKColor) -> UnitVisual {
        let container = SKNode()
        let r = radius(for: unit.definition.sizeClass)
        let shape = SKShapeNode(circleOfRadius: r)
        shape.fillColor = sideColor
        shape.strokeColor = eraColor(for: unit.definition.era)
        shape.lineWidth = 3
        container.addChild(shape)

        let hpLabel = SKLabelNode(fontNamed: "Menlo")
        hpLabel.fontSize = 10
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

    private func xPosition(for lanePosition: Double) -> CGFloat {
        let margin: CGFloat = 40
        let usableWidth = size.width - margin * 2
        let fraction = CGFloat(lanePosition / lane.length)
        return margin + usableWidth * fraction
    }

    private func updateLabels() {
        amberLabel.text = "Amber: \(amber)"
        playerBaseLabel.text = "Base: \(max(0, lane.playerBaseHP))"
        enemyBaseLabel.text = "Enemy Base: \(max(0, lane.enemyBaseHP))"
    }

    private func checkGameOver() {
        if lane.enemyBaseHP <= 0 {
            endGame(message: "YOU WIN")
        } else if lane.playerBaseHP <= 0 {
            endGame(message: "YOU LOSE")
        }
    }

    private func endGame(message: String) {
        isGameOver = true
        statusLabel.text = message
        statusLabel.isHidden = false
    }
}

// MARK: - SwiftUI host view

struct RoarFareContentView: View {
    @StateObject private var scene: BattleScene = {
        let scene = BattleScene(size: CGSize(width: 400, height: 300))
        scene.scaleMode = .resizeFill
        return scene
    }()

    // Era tab selection exists because deployOptions crossed 200 entries once the roster
    // expanded to 100 units -- a single flat scrolling list of every unit and every branch
    // stopped being usable mid-battle, so it's now split per-Era the same way the game's
    // core Era identity signal already works everywhere else (see ART_BIBLE.md §3.1).
    @State private var selectedEra: Era = .triassic

    private var visibleOptions: [DeployOption] {
        deployOptions.filter { $0.era == selectedEra }
    }

    var body: some View {
        VStack(spacing: 0) {
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if scene.isGameOver {
                Button("Play Again") {
                    scene.reset()
                }
                .padding(8)
                .background(Color.green.opacity(0.3))
                .cornerRadius(8)
                .padding(.top, 8)
            }

            Picker("Era", selection: $selectedEra) {
                ForEach(populatedEras, id: \.self) { era in
                    Text(era.displayName).tag(era)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal) {
                HStack {
                    ForEach(visibleOptions) { option in
                        let affordable = option.cost <= scene.amber
                        Button(option.label) {
                            scene.deployPlayerUnit(unitIndex: option.unitIndex, branchID: option.branchID)
                        }
                        .padding(8)
                        .background((affordable ? Color.blue : Color.gray).opacity(0.3))
                        .cornerRadius(8)
                        .disabled(!affordable)
                    }
                }
                .padding()
            }
        }
    }
}
