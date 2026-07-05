import Foundation

/// See `GAME_DESIGN.md` §3 — every unit's stat identity and trait counters are keyed off its Era.
public enum Era: String, Codable, CaseIterable, Sendable {
    case triassic
    case jurassic
    case cretaceous
    case iceAge
    case marine
    case sky
}
