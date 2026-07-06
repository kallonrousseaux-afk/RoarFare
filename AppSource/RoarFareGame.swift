import Foundation
import SpriteKit
import SwiftUI

// MARK: - Core types (mirrors RoarFareCore, inlined so this is a single drop-in file)

enum Era {
    case triassic, jurassic, cretaceous, iceAge, marine, sky
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
        deployCost: 60, baseStats: UnitStats(maxHP: 40, attackDamage: 8, attackIntervalSeconds: 0.6, rangeUnits: 1.0)
    ),
    UnitDefinition(
        id: "velociraptor", name: "Velociraptor", era: .cretaceous, sizeClass: .small, rarity: .rare,
        deployCost: 300, baseStats: UnitStats(maxHP: 120, attackDamage: 30, attackIntervalSeconds: 0.9, rangeUnits: 1.0)
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
        deployCost: 500, baseStats: UnitStats(maxHP: 420, attackDamage: 34, attackIntervalSeconds: 1.3, rangeUnits: 1.0, knockbackResistant: true)
    ),
    UnitDefinition(
        id: "stegosaurus", name: "Stegosaurus", era: .jurassic, sizeClass: .large, rarity: .rare,
        deployCost: 750, baseStats: UnitStats(maxHP: 700, attackDamage: 55, attackIntervalSeconds: 1.6, rangeUnits: 1.0, knockbackResistant: true)
    ),
    UnitDefinition(
        id: "ankylosaurus", name: "Ankylosaurus", era: .cretaceous, sizeClass: .large, rarity: .epic,
        deployCost: 800, baseStats: UnitStats(maxHP: 780, attackDamage: 48, attackIntervalSeconds: 1.4, rangeUnits: 1.2, knockbackResistant: true)
    ),
    UnitDefinition(
        id: "tyrannosaurus_rex", name: "Tyrannosaurus Rex", era: .cretaceous, sizeClass: .apex, rarity: .legendary,
        deployCost: 1800, baseStats: UnitStats(maxHP: 1600, attackDamage: 220, attackIntervalSeconds: 2.2, rangeUnits: 1.0, knockbackResistant: true)
    )
]

// MARK: - SpriteKit battle scene

final class BattleScene: SKScene {
    private var lane = Lane(length: 900, playerBaseHP: 1000, enemyBaseHP: 1000)
    private var lastUpdateTime: TimeInterval?
    private var amber: Double = 0
    private let amberPerSecond: Double = 20

    private var enemySpawnTimer: Double = 0
    private let enemySpawnCooldown: Double = 2.0

    private var isGameOver = false

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

    func deployPlayerUnit(at index: Int) {
        guard !isGameOver, bundledUnits.indices.contains(index) else { return }
        let unit = bundledUnits[index]
        guard Double(unit.deployCost) <= amber else { return }
        guard lane.deploy(unit, to: .player) else { return }
        amber -= Double(unit.deployCost)
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver else { return }
        let deltaTime = lastUpdateTime.map { currentTime - $0 } ?? 0
        lastUpdateTime = currentTime

        amber += amberPerSecond * deltaTime

        enemySpawnTimer += deltaTime
        if enemySpawnTimer >= enemySpawnCooldown, let randomUnit = bundledUnits.randomElement() {
            if lane.deploy(randomUnit, to: .enemy) {
                enemySpawnTimer = 0
            }
        }

        lane.tick(deltaTime: deltaTime)

        sync(units: lane.playerUnits, visuals: &playerVisuals, color: .systemBlue)
        sync(units: lane.enemyUnits, visuals: &enemyVisuals, color: .systemRed)
        updateLabels()
        checkGameOver()
    }

    private func sync(units: [DeployedUnit], visuals: inout [UUID: UnitVisual], color: SKColor) {
        var seenIDs = Set<UUID>()
        for unit in units {
            seenIDs.insert(unit.id)
            let visual: UnitVisual
            if let existing = visuals[unit.id] {
                visual = existing
            } else {
                visual = makeVisual(color: color)
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

    private func makeVisual(color: SKColor) -> UnitVisual {
        let container = SKNode()
        let shape = SKShapeNode(circleOfRadius: 14)
        shape.fillColor = color
        shape.strokeColor = .white
        container.addChild(shape)

        let hpLabel = SKLabelNode(fontNamed: "Menlo")
        hpLabel.fontSize = 10
        hpLabel.position = CGPoint(x: 0, y: 18)
        container.addChild(hpLabel)

        addChild(container)
        return UnitVisual(container: container, hpLabel: hpLabel)
    }

    private func xPosition(for lanePosition: Double) -> CGFloat {
        let margin: CGFloat = 40
        let usableWidth = size.width - margin * 2
        let fraction = CGFloat(lanePosition / lane.length)
        return margin + usableWidth * fraction
    }

    private func updateLabels() {
        amberLabel.text = "Amber: \(Int(amber))"
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
    @State private var scene: BattleScene = {
        let scene = BattleScene(size: CGSize(width: 400, height: 300))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some View {
        VStack(spacing: 0) {
            SpriteView(scene: scene)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView(.horizontal) {
                HStack {
                    ForEach(Array(bundledUnits.enumerated()), id: \.offset) { index, unit in
                        Button(unit.name) {
                            scene.deployPlayerUnit(at: index)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
    }
}
