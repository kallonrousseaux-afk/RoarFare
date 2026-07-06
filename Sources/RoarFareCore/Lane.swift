import Foundation

/// The core differentiator from Battle Cats' infinitely-stacking lane — see `GAME_DESIGN.md` §4.
/// Each side's frontline has a hard cap of 10 Blocking Units, plus a separate headcount cap for
/// Tiny units specifically (`tinyUnitHeadcountCap`); deploying a unit that would break either cap
/// is rejected outright rather than queued, so the caller (UI layer) can decide how to
/// communicate "no room right now" to the player.
///
/// BU accounting is position-aware: `currentBU(for:)` only counts units within
/// `frontlineEngagementRange` of that side's most-advanced alive unit (its "front tip") — a unit
/// that's fallen behind that cluster (e.g. via a knockback shove) stops counting, freeing room for
/// a new deployment even though it's still alive. `frontlineEngagementRange` (2.0) is deliberately
/// smaller than `knockbackDistance` (3.0) so a single landed knockback reliably drops the target
/// out of the count rather than leaving it borderline.
///
/// `tick(deltaTime:)` resolves one time-step of movement, single-target melee/ranged attacks,
/// base damage, knockback, the Era counter-damage multiplier (`EraCounters`), and evolution-branch
/// abilities (`Ability`) — attack-speed auras and first-hit damage bonuses.
public final class Lane {
    public static let frontlineBUCap = 10
    /// Tiny units get an additional headcount cap independent of the BU math — see
    /// `GAME_DESIGN.md` §4: aggregate BU alone would allow up to 10 Tiny units (10 x 1 BU), but
    /// the documented swarm cap is 6.
    public static let tinyUnitHeadcountCap = 6
    /// How far a landed knockback hit shoves the target back, in lane position units.
    public static let knockbackDistance = 3.0
    /// How close to a side's front-most alive unit another unit on that side needs to be to still
    /// count toward that side's frontline BU/headcount caps. See the type-level doc comment.
    public static let frontlineEngagementRange = 2.0

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

    /// BU used on `side`'s engaged frontline right now — see the type-level doc comment for what
    /// "engaged" means. A side with no alive units has 0 BU used, trivially.
    public func currentBU(for side: Side) -> Int {
        frontlineUnits(for: side).reduce(0) { $0 + $1.blockingUnits }
    }

    public func remainingBU(for side: Side) -> Int {
        max(0, Self.frontlineBUCap - currentBU(for: side))
    }

    private func tinyUnitCount(for side: Side) -> Int {
        frontlineUnits(for: side).filter { $0.definition.sizeClass == .tiny }.count
    }

    /// Alive units on `side` within `frontlineEngagementRange` of that side's front tip (its
    /// most-advanced alive unit). A side with only one alive unit trivially has that unit as its
    /// own front tip (distance 0), so a lone unit always counts regardless of where it personally
    /// is — there's nothing else on that side competing with it for frontline room yet.
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

    /// Returns `false` (and deploys nothing) if the unit's BU cost would push the side over the
    /// frontline cap, or — for Tiny units specifically — if the side is already at the headcount
    /// cap (`tinyUnitHeadcountCap`), which exists independent of and in addition to the BU cap.
    @discardableResult
    public func deploy(_ definition: UnitDefinition, activeBranchID: String? = nil, to side: Side) -> Bool {
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

    /// Applies damage to a unit by index on the given side. Returns `false` if the index is out
    /// of range. `tick(deltaTime:)` doesn't call this — it mutates `currentHP` directly since it
    /// already has the index in hand mid-loop; this method exists for tests and any other caller
    /// that needs to apply damage outside of a tick (e.g. a future ability effect).
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
            var stats = attackers[i].effectiveStats
            stats.attackIntervalSeconds *= Self.auraAttackIntervalMultiplier(for: attackers[i], allies: attackers)

            if attackers[i].attackCooldownRemaining > 0 {
                attackers[i].attackCooldownRemaining -= deltaTime
            }

            if let targetIndex = Self.nearestAliveDefenderInRange(
                from: attackers[i].position,
                range: stats.rangeUnits,
                defenders: defenders
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

    /// Applies `Ability.firstHitBonus` if `attacker` has one active and hasn't used it yet,
    /// marking it used. Otherwise returns `baseDamage` unchanged.
    private static func applyFirstHitBonus(to attacker: inout DeployedUnit, baseDamage: Int) -> Int {
        guard case .firstHitBonus(let multiplier)? = attacker.activeAbility, !attacker.hasUsedFirstStrike else {
            return baseDamage
        }
        attacker.hasUsedFirstStrike = true
        return Int((Double(baseDamage) * multiplier).rounded())
    }

    /// See `EraCounters` — applied to unit-vs-unit hits only, not base damage (bases aren't
    /// Era-typed).
    private static func eraAdjustedDamage(attackerEra: Era, defenderEra: Era, baseDamage: Int) -> Int {
        Int((Double(baseDamage) * EraCounters.damageMultiplier(attacker: attackerEra, defender: defenderEra)).rounded())
    }

    /// The strongest (lowest) `Ability.attackSpeedAura` multiplier among `unit`'s living
    /// same-side allies currently in range, or 1.0 (no effect) if none apply. Auras don't stack.
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
