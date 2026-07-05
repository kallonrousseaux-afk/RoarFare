import Foundation

/// Gacha pull-odds tier. Orthogonal to `Era` — see `GAME_DESIGN.md` §3:
/// a Common-rarity unit and a Legendary-rarity unit of the same Era share the same combat identity,
/// just different base numbers.
public enum Rarity: String, Codable, CaseIterable, Sendable {
    case common
    case rare
    case epic
    case legendary
}
