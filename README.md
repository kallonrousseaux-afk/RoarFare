# RoarFare

A dinosaur-themed lane tower-offense game in the spirit of *The Battle Cats*, differentiated by an era-based trait system, physical lane-blocking by creature size, and branching evolutions. Targeting iOS via Swift/SpriteKit, built in Xcode.

## Docs

- [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) — full game design document: core loop, era system, size classes, evolution, fossil dig gacha, extinction events, enemy/narrative arc, MVP scope, and tech notes.
- [`docs/ART_BIBLE.md`](docs/ART_BIBLE.md) — visual identity: tone, silhouette rules, color language (era palettes, rarity, factions), environment art, UI style, and branding.
- [`docs/MONETIZATION.md`](docs/MONETIZATION.md) — gacha economy and IAP spec: currency stack, purchasable SKUs, pity math, App Store loot-box compliance, and StoreKit 2 implementation notes.

## Code

`RoarFareCore` is a Swift package (this repo's root `Package.swift`) covering the two systems `GAME_DESIGN.md` calls the actual differentiators from Battle Cats:

- **The unit data model** (`Sources/RoarFareCore/UnitDefinition.swift`, `EvolutionBranch.swift`, `UnitStats.swift`) — units are data (`Resources/units.json`), not per-unit subclasses. 8 hand-authored units are bundled, covering every size class plus the two branching-evolution examples from §5 (Deinonychus, Parasaurolophus).
- **The lane's Blocking-Unit cap** (`Sources/RoarFareCore/Lane.swift`) — the hard 10 BU frontline limit from §4, with tests in `Tests/RoarFareCoreTests/` covering the cap math directly.
- **Combat tick simulation** (`Lane.tick(deltaTime:walkSpeed:)`) — single-target melee/ranged combat: units walk toward the opposing end, stop and fight when an enemy or the opposing base is in range, and defeated units clear automatically (freeing their BU back up). Knockback isn't modeled yet.

This repo was authored outside Xcode — no Swift toolchain is available in that environment (network policy blocks `download.swift.org`), so everything here was written and checked without a compiler: JSON validated with `python3 -m json.tool`, brace balance checked per file, and every test manually traced against the implementation logic by hand. Open the package in Xcode (`File > Open` on `Package.swift`) to actually build and run the test suite — that's the first thing to do with this code, since it hasn't been compiled yet.
