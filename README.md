# RoarFare

A dinosaur-themed lane tower-offense game in the spirit of *The Battle Cats*, differentiated by an era-based trait system, physical lane-blocking by creature size, and branching evolutions. Targeting iOS via Swift/SpriteKit, built in Xcode.

## Docs

- [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) — full game design document: core loop, era system, size classes, evolution, fossil dig gacha, extinction events, enemy/narrative arc, MVP scope, and tech notes.
- [`docs/ART_BIBLE.md`](docs/ART_BIBLE.md) — visual identity: tone, silhouette rules, color language (era palettes, rarity, factions), environment art, UI style, and branding.
- [`docs/MONETIZATION.md`](docs/MONETIZATION.md) — gacha economy and IAP spec: currency stack, purchasable SKUs, pity math, App Store loot-box compliance, and StoreKit 2 implementation notes.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — the step-by-step path from this repo's current state to a shipped App Store game: phase-by-phase goals, steps, and exit criteria, starting with "get this compiling in Xcode."

## Code

`RoarFareCore` is a Swift package (this repo's root `Package.swift`) covering the two systems `GAME_DESIGN.md` calls the actual differentiators from Battle Cats:

- **The unit data model** (`Sources/RoarFareCore/UnitDefinition.swift`, `EvolutionBranch.swift`, `UnitStats.swift`) — units are data (`Resources/units.json`), not per-unit subclasses. **20 units are bundled right now** — deliberately trimmed back from a 100-unit expansion (still in git history, commit `b18bde7`) to just the units with complete character art (base + every evolution branch illustrated), so there's a fully-dressed roster to actually playtest instead of 80 units still rendering as bare placeholder circles. The other 80 go back in once their art is done — see "Known gaps" below. Every bundled unit has at least one evolution branch; the three legendary-rarity units (Tyrannosaurus Rex, Brachiosaurus, Spinosaurus) have two each, as do Deinonychus and Parasaurolophus (the original §5 branching examples, rare/common rarity, despite not being legendary themselves).
- **The lane's Blocking-Unit cap** (`Sources/RoarFareCore/Lane.swift`) — the hard 10 BU frontline limit from §4, plus the separate 6-unit Tiny headcount cap (independent of BU math). Both are position-aware: `currentBU(for:)` only counts units within `frontlineEngagementRange` of that side's front tip, so a knockback shove can drop a unit out of the count (and free the room) even though it's still alive — see the `Lane.swift` header comment for exactly how "engaged at the front" is defined.
- **Combat tick simulation** (`Lane.tick(deltaTime:walkSpeed:)`) — single-target melee/ranged combat: units walk toward the opposing end, stop and fight when an enemy or the opposing base is in range, defeated units clear automatically (freeing their BU back up), attacks flagged `dealsKnockback` shove non-resistant targets back, and damage is adjusted by the Era counter table (`EraCounters`) and any active evolution-branch ability (`Ability` — currently an attack-speed aura and a first-hit damage bonus).
- **Evolution-branch abilities** (`Ability.swift`) — Herd Caller's aura and Ambush Striker's first-hit-then-revert bonus from `GAME_DESIGN.md` §5 are real, executable behavior now, not just flavor text in `abilityDescription`.

**Known gaps, documented rather than silently left in place:** the Era counter table only models 2 of the several relationships described in `GAME_DESIGN.md` §3 (the rest depend on an armor stat and an enemy-trait system that don't exist yet); there's no same-side unit collision at all (units can't physically block or queue behind each other, they just occupy the same space) — see the `Lane.swift` header comment and `GAME_DESIGN.md` §11 item 7 for the details on both; the roster is temporarily 20 units instead of 100 (see above) pending the rest of the character-art pass.

An independent review pass caught several doc/code inconsistencies that have since been fixed: a stale gacha pity number in `GAME_DESIGN.md` that disagreed with `MONETIZATION.md`, a PvP section in `MONETIZATION.md`'s benchmarking table that contradicted the full Rival Grounds spec built later, a size-class mismatch between two units' documented examples and their actual `units.json` entries, a broken `§4.5` cross-reference, and the Tiny headcount cap described in the design doc but never enforced in code (now fixed, with the misleading test that had demonstrated the bug corrected alongside it).

This repo was authored outside Xcode — no Swift toolchain is available in that environment (network policy blocks `download.swift.org`), so everything here was written and checked without a compiler: JSON validated with `python3 -m json.tool`, brace balance checked per file, and every test manually traced against the implementation logic by hand. Open the package in Xcode (`File > Open` on `Package.swift`) to actually build and run the test suite — that's the first thing to do with this code, since it hasn't been compiled yet.

## Playable app (`AppSource/RoarFareGame.swift`)

A single self-contained Swift file (no package dependency) with the same game logic inlined, plus a SpriteKit battle scene and a SwiftUI host view (`RoarFareContentView`) — this is what actually runs as an app in Xcode's Simulator, confirmed building and launching successfully (Phase 0/1 of `docs/ROADMAP.md`).

- Player and enemy each have their own Amber-style economy gating what they can deploy — the enemy can only spawn what it can currently afford, checked twice a second (an earlier draft spawned a uniformly random unit, including the most expensive one, on a flat timer with no cost check at all — a real bug, not a design choice, fixed once actually reasoned through).
- Every unit's evolution branch(es) are reachable as their own deploy button, not just the base form — including all three legendary units' two branches each. Deploy buttons are split into Era tabs (Triassic/Jurassic/Cretaceous) so the list stays browsable as the roster grows back toward 100.
- `BattleScene.reset()` + a "Play Again" button let a finished match restart without relaunching the app.
- Placeholder unit visuals vary by BU size class (circle radius) and Era (ring color) instead of every unit being an identical dot — still not real art (see `docs/ART_BIBLE.md` for that), but the mechanics that actually differentiate units are visible on screen now.

To add this to an Xcode project: create a plain iOS App (SwiftUI) target, drag `AppSource/RoarFareGame.swift` in (no other files, no package dependencies needed), and point the `@main` App struct's `WindowGroup` at `RoarFareContentView()` instead of the template's `ContentView()`.
