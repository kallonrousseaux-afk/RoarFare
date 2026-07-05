import Foundation

/// See `GAME_DESIGN.md` §4 — Blocking Units (BU) are how RoarFare's lane differs from Battle Cats'
/// infinite-stacking lane. The frontline has a hard 10 BU cap; see `Lane.frontlineBUCap`.
public enum SizeClass: String, Codable, CaseIterable, Sendable {
    case tiny
    case small
    case medium
    case large
    case apex

    public var blockingUnits: Int {
        switch self {
        case .tiny: return 1
        case .small: return 2
        case .medium: return 3
        case .large: return 5
        case .apex: return 8
        }
    }
}
