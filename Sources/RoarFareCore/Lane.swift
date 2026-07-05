import Foundation

/// The core differentiator from Battle Cats' infinitely-stacking lane — see `GAME_DESIGN.md` §4.
/// Each side's frontline has a hard cap of 10 Blocking Units; deploying a unit that would push a
/// side over the cap is rejected outright rather than queued, so the caller (UI layer) can decide
/// how to communicate "no room right now" to the player.
///
/// This type only enforces the BU cap and tracks who's alive on which side. It intentionally does
/// not implement movement, attack timing, or knockback yet — that tick-by-tick combat simulation
/// is the next pass, once this can be built and iterated on directly in Xcode rather than written
/// blind without a compiler.
public final class Lane {
    public static let frontlineBUCap = 10

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

    private func units(for side: Side) -> [DeployedUnit] {
        side == .player ? playerUnits : enemyUnits
    }
}
