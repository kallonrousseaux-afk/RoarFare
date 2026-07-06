import Foundation

/// The core differentiator from Battle Cats' infinitely-stacking lane — see `GAME_DESIGN.md` §4.
/// Each side's frontline has a hard cap of 10 Blocking Units; deploying a unit that would push a
/// side over the cap is rejected outright rather than queued, so the caller (UI layer) can decide
/// how to communicate "no room right now" to the player.
///
/// `tick(deltaTime:)` resolves one time-step of movement, single-target melee/ranged attacks,
/// base damage, and knockback — see `GAME_DESIGN.md` §4: knockback is how a jammed frontline
/// clears BU space mid-fight, since a shoved-back unit's position (and therefore its BU claim
/// on the front) moves with it.
public final class Lane {
    public static let frontlineBUCap = 10
    /// How far a landed knockback hit shoves the target back, in lane position units.
    public static let knockbackDistance = 3.0

    public let length: Double
    public private(set) var playerUnits: [DeployedUnit] = []
    public private(set) var enemyUnits: [DeployedUnit] = []
    public private(set) var playerBaseHP: Int
    public private(set) var enemyBaseHP: Int

    public init(length: Double = 100, playerBaseHP: Int = 1000, enemyBaseHP: Int = 1000) {
        self.length = length
        self.playerBaseHP = playerBaseHP
        self.enemyBaseHP = enemyBaseHP
    }

    public func currentBU(for side: Side) -> Int {
        units(for: side).reduce(0) { $0 + $1.blockingUnits }
    }

    public func remainingBU(for side: Side) -> Int {
        max(0, Self.frontlineBUCap - currentBU(for: side))
    }

    /// Returns `false` (and deploys nothing) if the unit's BU cost would push the side over the
    /// frontline cap.
    @discardableResult
    public func deploy(_ definition: UnitDefinition, activeBranchID: String? = nil, to side: Side) -> Bool {
        guard currentBU(for: side) + definition.sizeClass.blockingUnits <= Self.frontlineBUCap else {
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

    /// Applies damage to a unit by index on the given side. Returns `false` if the index is out
    /// of range. This exists mainly for tests today; the future combat-tick pass (see file-level
    /// doc comment above) will be the real caller once it lands.
    @discardableResult
    public func applyDamage(_ amount: Int, toUnitAt index: Int, side: Side) -> Bool {
        switch side {
        case .player:
            guard playerUnits.indices.contains(index) else { return false }
            playerUnits[index].currentHP -= amount
            return true
        case .enemy:
            guard enemyUnits.indices.contains(index) else { return false }
            enemyUnits[index].currentHP -= amount
            return true
        }
    }

    /// Removes dead units, freeing up their BU on the frontline for new deployments.
    public func clearDefeatedUnits() {
        playerUnits.removeAll { !$0.isAlive }
        enemyUnits.removeAll { !$0.isAlive }
    }

    /// Advances the battle by `deltaTime` seconds. Each alive unit either fights (if an enemy
    /// unit, or the opposing base itself, is within its range) or walks toward the opposing end
    /// of the lane. Player units resolve first each tick, then enemy units — a fixed, documented
    /// turn order (matching the convention Plants vs. Zombies Heroes uses, per the research in
    /// `GAME_DESIGN.md` §14.2) rather than an arbitrary one. Dead units are cleared at the end of
    /// the tick, which is also what frees their BU back up for new deployments (`deploy(_:to:)`).
    public func tick(deltaTime: Double, walkSpeed: Double = 5.0) {
        resolveCombatAndMovement(
            attackers: &playerUnits,
            defenders: &enemyUnits,
            advancesTowardIncreasingPosition: true,
            defendersBaseHP: &enemyBaseHP,
            deltaTime: deltaTime,
            walkSpeed: walkSpeed
        )
        resolveCombatAndMovement(
            attackers: &enemyUnits,
            defenders: &playerUnits,
            advancesTowardIncreasingPosition: false,
            defendersBaseHP: &playerBaseHP,
            deltaTime: deltaTime,
            walkSpeed: walkSpeed
        )
        clearDefeatedUnits()
    }

    private func resolveCombatAndMovement(
        attackers: inout [DeployedUnit],
        defenders: inout [DeployedUnit],
        advancesTowardIncreasingPosition: Bool,
        defendersBaseHP: inout Int,
        deltaTime: Double,
        walkSpeed: Double
    ) {
        for i in attackers.indices {
            guard attackers[i].isAlive else { continue }
            let stats = attackers[i].effectiveStats

            if attackers[i].attackCooldownRemaining > 0 {
                attackers[i].attackCooldownRemaining -= deltaTime
            }

            if let targetIndex = Self.nearestAliveDefenderInRange(
                from: attackers[i].position,
                range: stats.rangeUnits,
                defenders: defenders
            ) {
                if attackers[i].attackCooldownRemaining <= 0 {
                    defenders[targetIndex].currentHP -= stats.attackDamage
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
                    defendersBaseHP -= stats.attackDamage
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

    private static func nearestAliveDefenderInRange(
        from position: Double,
        range: Double,
        defenders: [DeployedUnit]
    ) -> Int? {
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
