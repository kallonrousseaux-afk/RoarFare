# RoarFare — Game Design Document

**Genre:** Gacha tower-offense (Battle Cats–style lane pusher)
**Theme:** Prehistoric life, extinction, and evolution
**Target platform:** iOS (Swift / SpriteKit), built with Xcode
**Status:** Pre-production / design lock

---

## 1. Pitch

RoarFare is a lane-based tower-offense game in the lineage of *The Battle Cats*: you deploy units on a single-lane battlefield to push toward and destroy the enemy base while your own base takes fire. The reskin is dinosaurs — but the differentiation isn't fur-to-scales. Three systems that Battle Cats doesn't have are load-bearing here:

1. **Eras** replace flat rarity tiers — every unit belongs to a geologic period with its own stat identity and counters.
2. **Size classes physically occupy lane space** — big units block the lane, small units swarm through gaps.
3. **Evolution branches into roles**, not just bigger numbers.

Everything else (fossil digs, extinction events, pack hunting, the enemy roster) is built to reinforce those three systems, not to sit alongside them as flavor.

---

## 2. Core Loop

1. Player picks a squad (10 unit slots) from their collection for a given stage.
2. Stage plays out in real time: currency (**Amber**) accrues, spent to deploy units into the lane.
3. Units auto-walk toward the enemy base, auto-attack whatever's in range, and get auto-attacked back.
4. Player wins by destroying the enemy base; loses if their own base HP hits 0.
5. Post-stage: rewards include Amber, XP, and **Fossil Fragments** (currency for the gacha layer).
6. Meta-loop: dig fossils → pull/level/evolve units → tackle harder stages → unlock new eras/biomes.

This loop is intentionally close to Battle Cats' — the differentiation lives inside step 3 and the meta-loop, not in the loop's shape.

---

## 3. The Era System

Instead of Battle Cats' Rare/Special/Uber rarity ladder (which is purely a pull-odds tier), every unit has an **Era** that determines its base stat profile and its trait interactions. Rarity (Common/Rare/Epic/Legendary) still exists for gacha odds, but it's orthogonal to Era — a Common-rarity Jurassic unit and a Legendary-rarity Jurassic unit share the same combat identity, just different numbers.

| Era | Stat identity | Design role |
|---|---|---|
| **Triassic** | Low HP, low cost, very fast attack speed | Early-game swarm, cheap chip damage, "starter" era |
| **Jurassic** | High damage, slow attack speed, big hitbox | Heavy hitters, single-target burst, expensive |
| **Cretaceous** | Balanced stats, unique abilities (armor plating, horns, ranged) | Tactical/utility era, most trait diversity |
| **Ice Age** | Moderate stats, on-hit slow/freeze effects | Crowd control, anti-swarm |
| **Marine** (bonus sub-era, deployed only on coastal stages) | High HP, area-denial, can't be knocked back | Stage-gated specialists |
| **Sky** (bonus sub-era — pterosaurs) | Ignores ground-only enemies, low HP, hit-and-run | Counters "flying" enemy trait |

**Trait/counter web** (rock-paper-scissors layer, analogous to Battle Cats' Red/Floating/Black/Metal):
- Ice Age slows counter Triassic swarms.
- Jurassic burst counters Cretaceous armor (armor mitigates DPS, not burst).
- Cretaceous ranged/utility counters Jurassic's slow attack speed (kite them).
- Triassic swarm counters single-target Jurassic units (surround before they land a hit).
- Sky counters "Burrower" enemy trait (see §9) which ignores ground units entirely.

This gives four-plus-way rock-paper-scissors instead of Battle Cats' cleaner but flatter trait chart — intentional, since Eras also carry narrative/unlock weight (you literally unlock eras in sequence as you progress, like unlocking Crazed/Behemoth stages).

---

## 4. Size Classes & Lane Blocking

This is the single biggest mechanical departure from Battle Cats, where units stack infinitely in a lane. In RoarFare, **the lane has physical width**, measured in **Blocking Units (BU)**:

| Size Class | BU cost | Examples | Behavior |
|---|---|---|---|
| **Tiny** | 1 BU | Compsognathus, Microraptor | Up to 6 can occupy the lane's frontline simultaneously; die in 1-2 hits but swarm past big blockers |
| **Small** | 2 BU | Velociraptor, Dilophosaurus | Standard DPS/skirmish units |
| **Medium** | 3 BU | Triceratops, Parasaurolophus | Frontline tanks, knockback-resistant |
| **Large** | 5 BU | Ankylosaurus, Stegosaurus | Heavy tank, high knockback resistance, area attacks |
| **Apex** | 8 BU (lane cap is 10 BU) | T. Rex, Spinosaurus, Giganotosaurus | Only 1 fits on the frontline at a time; massive single-target damage, cannot be knocked back at all, but a screen full of Tiny units can slip past them once they're engaged |

The lane has a **10 BU frontline cap**. This means:
- Deploying an Apex unit (8 BU) all but locks the frontline — only 2 BU of anything else fits alongside it (e.g., one Tiny unit).
- Swarm strategies (six Tiny units = 6 BU) leave room to layer a Medium tank behind them.
- Enemies have BU costs too, so the player must reason about "can I even fit a counter-unit into this lane right now," a resource-management axis Battle Cats never has (Battle Cats units always fit; the constraint there is purely economic/cost, not spatial).

Knockback (an existing Battle Cats mechanic) interacts with BU: strong hits shove a non-resistant target back a fixed distance ("a lane segment" — in the current implementation, `Lane.knockbackDistance`), which clears frontline BU space mid-fight if it moves the target out of the engaged frontline — so knockback becomes a way to *unstick* a jammed lane, not just a damage-mitigation dodge. **Implementation status:** this is now real, not just a description. `Lane.currentBU(for:)` only counts units within `Lane.frontlineEngagementRange` of that side's most-advanced alive unit ("front tip") — a unit knocked out of that window stops counting toward the cap even though it's still alive, freeing room for a new deployment. `frontlineEngagementRange` (2.0) is deliberately smaller than `knockbackDistance` (3.0) so a single landed knockback reliably drops the target out of the count. A lone unit on an otherwise-empty side is trivially its own front tip (distance 0), so it always counts regardless of its position — the mechanic only matters once a side has more than one unit and knockback separates one from the pack.

---

## 5. Units, Roles, and Branching Evolution

Battle Cats evolution is linear (Normal → Evolved → True → Ultra), and it's almost always a pure upgrade. RoarFare evolution is **branching**: at the "Evolved" tier, most units choose one of two divergent forms that change their *role*, not just their stats. You keep both branches unlocked once discovered, but a given deployed copy is one or the other (re-evolving a second copy lets you run both).

Example — **Parasaurolophus** (Cretaceous, Medium):
- **Base form:** balanced herbivore, moderate HP/damage, no special ability.
- **Branch A — "Herd Caller":** loses personal damage, gains an aura that buffs attack speed of all units within 2 lane segments. Becomes a support unit.
- **Branch B — "Skull-Crest Rammer":** gains bonus knockback-resistance and a charge attack with heavy knockback on hit. Becomes an anti-swarm tank.

Example — **Deinonychus** (Cretaceous, Small):
- **Base form:** fast attacker, average damage.
- **Branch A — "Pack Leader":** unlocks the Pack Hunting bonus (see §6) when fielded with other raptors.
- **Branch B — "Ambush Striker":** first attack after being deployed deals 3x damage (opening-alpha-strike role), then reverts to normal.

Every unit's evolution tree is documented as: Base → (Branch A / Branch B), each with its own icon variant, so the collection screen visually reflects the build decision, not just a level number.

**Progression currency for evolution:** in-stage-drop "Evolution Catalysts" specific to each biome, mirroring Battle Cats' Catfruit system but reframed as fossilized biological material specific to where the animal lived. (Fossil Fragments are the Dig Site pull currency and fund unit *leveling* — see §10 and `MONETIZATION.md` §1 — evolution runs on Catalysts alone so the two progression tracks don't compete for the same currency.)

**Implementation status of branch-specific abilities:** both example behaviors above are now real, executable code, not just `abilityDescription` flavor text. `RoarFareCore`'s `Ability` type covers exactly these two shapes — `.attackSpeedAura(range:attackIntervalMultiplier:)` for Herd Caller and `.firstHitBonus(damageMultiplier:)` for Ambush Striker — resolved inside `Lane.tick()`. This is deliberately still a small, closed set of ability *shapes* rather than a general scripting system: adding a branch with a genuinely new kind of behavior (not an aura or a first-hit bonus) means adding a new `Ability` case and wiring it into `Lane.tick()`, not just describing it in JSON. Multiple overlapping auras don't stack (strongest single multiplier wins) — that's a deliberate simplification, not an oversight.

---

## 6. Pack Hunting (Social/Synergy Layer)

Certain units (mostly Small/Tiny predators — raptors, troodontids) have abilities that only activate when specific squadmates are also on the field:

- **Velociraptor + Deinonychus + Utahraptor fielded together:** each gains +15% attack speed ("Pack Bonus: Raptor Pack").
- **Any 3+ Ceratopsian units (Triceratops, Styracosaurus, Pentaceratops) on the field:** they form a "Wall" — while adjacent, their combined knockback resistance is treated as one unit's worth (i.e., you have to kill all three near-simultaneously to break the line).
- **Parasaurolophus "Herd Caller" + any 2 herbivores:** herd-wide heal-over-time.

This gives squad-building a second axis beyond Era/BU math: some squads are built around unlocking synergy bonuses, which Battle Cats' independent-unit design never asked players to do. Pack Hunting bonuses are always additive/supportive (never required to clear content) so they stay a build optimization, not a mandatory gate.

---

## 7. Fossil Dig (Gacha Meta-Layer)

Reframes Battle Cats' Cat Capsule gacha as **Dig Sites**:

- Each Dig Site is themed to a biome (Desert Dig, Arctic Dig, Swamp Dig, Coastal Dig, Volcanic Dig) and its pull pool is weighted toward Eras/units native to that biome (Desert Dig favors Cretaceous ceratopsians and ankylosaurs; Arctic Dig favors Ice Age megafauna).
- Currency: **Fossil Fragments**, earned from stage clears and log-in rewards; premium currency **Amber Shards** can buy Fragments directly (this is the monetization-equivalent slot Battle Cats fills with Cat Food).
- Pity system: a hard pity must exist — no fully unbounded gacha. Exact pull counts are specified once, in `MONETIZATION.md` §3, and shouldn't be duplicated here to avoid the two docs drifting out of sync (they already did once — an earlier draft of this line said "every 200," which `MONETIZATION.md` §3 later revised down to 90 against genre benchmarks, and this line wasn't updated to match until this pass).
- **Banner site rotation:** limited-time Dig Sites (e.g., "Feathered Dinosaurs Dig," "Marine Reptile Dig") introduce new Eras/sub-eras gradually rather than launching the full roster day one.

Rate transparency and a hard pity are non-negotiable design requirements, not just a nice-to-have — App Store policy requires disclosed odds for loot-box mechanics, and a hard pity keeps the system from reading as predatory.

**Full monetization spec (currencies, IAP catalog, pull costs, pity math, App Store compliance, StoreKit implementation) lives in [`docs/MONETIZATION.md`](MONETIZATION.md) — read that before building the Dig Site or purchase flow.**

---

## 8. Extinction Events (Endgame Modes)

Battle Cats' analog is Special/Catclaw Dojo stages with unusual rule modifiers. RoarFare frames the same idea narratively:

- **Meteor Strike Event:** periodic global rule-modifier stages where a "meteor timer" counts down; if the player hasn't destroyed the enemy base before it hits zero, ALL units (both sides) take escalating burn damage per tick — forces aggressive, fast-clear play rather than turtling.
- **Ice Age Event:** stage-wide slow field affects both sides' non-Ice-Age units; only Ice Age-Era units are unaffected — a stage practically designed to force players to field an off-meta Era.
- **Volcanic Event:** lane hazard zones periodically erupt, damaging whatever's standing in them regardless of side — adds a positioning/timing puzzle on top of the usual deploy-timing puzzle.
- **The Great Dying (top-tier raid stage):** an ultra-hard capstone raid themed around the Permian extinction, gated behind clearing all four standard Extinction Events once — this is RoarFare's answer to Battle Cats' Behemoth Stones/Zero Legends, i.e., the "prestige raid" slot.

Each event is time-limited (rotates weekly/monthly) and drops event-exclusive Evolution Catalysts, giving them a reason to run beyond bragging rights.

---

## 9. Enemy Design & Meta-Narrative Arc

Battle Cats' enemy trait roster (Traitless / Red / Floating / Black / Metal / Angel / Alien / Zombie / Relic) is replaced with a **thematically-motivated, escalating cast** that also tells a story across the campaign:

| Tier | Enemy faction | Trait | Narrative framing |
|---|---|---|---|
| 1 | **Rival Dinosaurs** | Traitless | Contemporary predators/herbivores from other territories — basic tutorial-tier threats |
| 2 | **Burrowers** | Ignores ground-based melee unless it also has Sky or anti-Burrower trait | Ancient burrowing reptiles/insects — forces Sky-Era counter-picks |
| 3 | **Leviathans** | High HP, slow, area-denial (Marine stages) | Giant marine reptiles (Mosasaurs, Plesiosaurs) — coastal-stage gatekeepers |
| 4 | **Swarmkind** | Numerous, individually weak, high aggregate BU pressure | Giant prehistoric insects/arthropods — punishes players who only bring Apex units (BU-starved lane) |
| 5 | **Ashborn** | Fire/lava-themed, burn DoT on hit | Volcanic-event-native threats |
| 6 (final act) | **The Mammal Ascendant** | Small, adaptive, gains a permanent small stat buff every time the player loses a stage against them ("adapts") | Framed as the extinction-event antagonist faction — early mammals (and eventually proto-humans) rising as the dinosaurs' era ends. This flips the real-world extinction narrative into the final boss arc: the player spends the whole game being the apex, then has to fight the thing that outlasts them |

This gives the campaign an actual narrative arc (rival dinos → environmental threats → the thing that replaces you) instead of being reskinned generic waves, and it's the main story-driven differentiator from Battle Cats, which is intentionally light on lore.

---

## 10. Progression & Economy Overview

- **Base currencies:** Amber (in-stage deploy currency, also soft meta-currency for basic upgrades), Fossil Fragments (gacha pulls), Evolution Catalysts (biome-specific evolution material), Amber Shards (premium — see [`docs/MONETIZATION.md`](MONETIZATION.md) for the full IAP catalog and gacha economy this currency drives).
- **Unit leveling:** flat XP-based level-up using Fossil Fragments, capped per rarity tier (mirrors Battle Cats' Cat Food + XP leveling, no departure needed here — it isn't a differentiation lever worth spending novelty budget on). Amber is intentionally not part of leveling — it stays a pure in-battle deploy currency (`MONETIZATION.md` §1), so it never doubles as a meta-progression spend.
- **Stage structure:** World Map → Biome (group of ~12 stages) → Boss stage → unlocks next Biome + its Dig Site. Biomes double as both level packs and gacha-pool themes, so map progression and collection-building reinforce each other.
- **Energy/stamina system:** standard timed-regen stamina gate per stage attempt (same as Battle Cats' Energy) — not a differentiation target, keep it standard.

---

## 11. MVP Scope (for a Claude + Xcode build)

Building the whole system above at once is not a v1. Recommended MVP cut, in order:

1. **Lane + BU system** (the core differentiator) with 3 Eras (Triassic, Jurassic, Cretaceous) and Tiny/Small/Medium/Large/Apex sizes — no Marine/Sky yet.
2. **8–10 hand-authored units** covering every size class and at least one branching evolution example end-to-end.
3. **One biome's worth of stages** (8-10 stages) using Tier 1-2 enemies only (Rival Dinosaurs, Burrowers).
4. **A single Dig Site** with a basic pity counter and the copy-ladder duplicate system (`MONETIZATION.md` §3.1) — defer banner rotation and premium currency to post-MVP.
5. **The Fossil Record** (§13) — cheap to build (a discovery flag + one-time reward per unit) and worth including alongside the Dig Site rather than deferring.
6. Defer: Pack Hunting synergies, Extinction Events, Marine/Sky sub-eras, the full 6-tier enemy arc, and Rival Grounds PvP (§14) — PvP in particular needs a backend for snapshot storage/matchmaking that the MVP's offline-first scope doesn't otherwise require, so it comes after the core PvE loop is proven, not alongside it.
7. **Update:** the abilities engine and a first slice of the Era counter web are done, ahead of this originally-deferred schedule — see §5's implementation-status note and `EraCounters` (only Ice Age-vs-Triassic and Jurassic-vs-Cretaceous are modeled as flat damage multipliers so far). Still genuinely deferred: the *rest* of §3's web (armor/mitigation as a real stat, ranged-kites-slow and swarm-surrounds-single-target as anything beyond what already falls out of existing range/attack-speed/BU stats, and the Sky-vs-Burrower relationship, which needs an enemy-trait system that doesn't exist yet) — those need more data-model scaffolding (an armor stat, an enemy-trait tag system) than was safe to add in the same pass as the first two items.

This scope proves out the lane-blocking mechanic and branching evolution — the two systems that make RoarFare not just a reskin — before investing in the meta-layer breadth.

---

## 12. Tech Notes (Swift / Xcode)

- **Engine:** SpriteKit is sufficient for a 2D single-lane tower-offense game and integrates natively with Xcode/Swift without a third-party engine dependency; SwiftUI can wrap the meta-game screens (collection, dig site, world map) around an `SKScene`-hosted battle view.
- **Data-driven units:** define units as Swift `Codable` structs backed by a bundled JSON (or `.plist`) table (Era, size class/BU cost, HP, damage, attack speed, range, evolution branch refs — trait/counter-web fields per §3 are deferred along with the rest of that system, see §11) rather than hardcoding per-unit subclasses — this keeps adding the ~100+ unit roster from becoming a code-scale problem, and lets Claude generate/edit unit data as structured JSON rather than Swift code. **Codable gotcha:** default parameter values on a struct's memberwise initializer are not used by Swift's synthesized `Decodable` conformance — every field needs an explicit value in the JSON regardless of what default the Swift `init` declares, or decoding throws on a missing key.
- **Lane/BU collision:** model the lane as a 1D coordinate space with per-unit BU "footprint," not a full 2D physics simulation — resolve blocking as a simple occupied-width check, since real physics is unnecessary overhead for a lane game.
- **Save data / gacha state:** local persistence via `SwiftData` (or `Codable` + file storage) is enough for an offline-first MVP; only add a backend once live-ops (banner rotation, leaderboards) is actually in scope.
- **PvP backend:** CloudKit is a reasonable first choice for Tier 1 — it can store defense-squad snapshots and drive matchmaking/leaderboards without standing up custom server infrastructure, and it's already first-party in the Apple toolchain. For Tier 2, use GameKit's `GKMatch` for real-time transport instead of building a custom server (see §14.2) — Apple's matchmaking/relay covers this natively in Swift. Reserve an actual third-party authoritative server for the point (if ever) Tier 2 becomes competitively significant enough that GameKit's peer-to-peer trust model stops being good enough.

---

## 13. Genre Alignment Notes

Checked this design against current popularity patterns and standard gimmicks in the tower-defense/hero-collector gacha genre (Battle Cats, Arknights, and the broader Genshin-style gacha mainstream). Most of what's genre-standard was already covered by design (banner rotation, battle pass, seasonal events, disclosed odds — see `MONETIZATION.md` §7 for the full comparison table). Four things came out of that pass:

1. **Fossil Record (collection-log system) — small addition, worth building into the MVP.** Battle Cats' Cat Guide rewards players with Cat Food just for having discovered each unit at all, independent of gacha luck otherwise — a cheap, high-retention "collector" hook. RoarFare's equivalent is the **Fossil Record**: a per-biome specimen log that shows every unit (silhouetted until discovered, per the museum-placard framing in the Art Bible §6) and pays out a small one-time Fossil Fragment/Amber Shard bonus the first time a player pulls each unit — first copy only, no relation to the duplicate/Mastery system in `MONETIZATION.md` §3.1. Cheap to build (it's just a discovery flag per unit plus a reward trigger) and directly reinforces the paleontologist-collector fantasy the Art Bible is already built around, so it's worth including in the MVP cut (§11) rather than deferring.
2. **Guest Dino (support-borrow system) — recommended post-MVP addition.** Arknights' Support Unit and Fire Emblem Heroes' friend-unit systems (borrow a friend's or a random other player's high-rarity unit, free, for a single stage attempt) are consistently cited as one of the genre's best-liked features: they flatten early-game difficulty spikes without giving anything away permanently, and they double as a soft flex/social hook (seeing a friend's cool Apex-tier dino). RoarFare doesn't have this yet. It's deliberately excluded from the MVP cut (§11) since it needs a minimal backend (fetching another player's unit data) that the MVP's offline-first scope doesn't otherwise require — but it should be the first meta-feature added once a backend exists for banner rotation anyway.
3. **Collab-ready banner framing — no build change needed now, but a naming/scope note.** Crossover events are historically Battle Cats' single biggest engagement and revenue driver. RoarFare is an original IP, so licensed collabs aren't available at launch, but the Dig Site/banner system (§7) is already generic enough to host a themed "guest era" later — either an in-universe special-event cast or an eventual licensed crossover. No structural change needed; just don't hardcode banner theming assumptions that would make a future guest-era event awkward to slot in.
4. **PvP/multiplayer.** Roughly half of new titles in the genre now ship some multiplayer feature; Battle Cats itself never has, and PvP puts real competitive-balance pressure on a roster designed around collection/build-expression fantasy (§5, §6) rather than head-to-head fairness. That tension doesn't go away just because we're building the mode — see §14 for the design, and note it's still excluded from the MVP cut (§11); it's a post-launch addition once the core PvE loop and a backend already exist.

---

## 14. PvP Mode: Rival Grounds

Two tiers, built in sequence. Both reuse the existing lane + BU combat simulation (§4) rather than inventing a second battle system — that's what keeps this affordable to build on top of everything else in this doc.

### 14.1 Tier 1 — Asynchronous Arena (the version to actually build first)

This is almost exactly Summoners War's Arena and AFK Arena's PvP loop: set a defense team, it fights other players' attacks via AI/script while you're offline, and you separately spend your own attempts climbing a ladder against other players' snapshots. Confirming RoarFare's version against that precedent didn't change the design, just validated it — no live netcode, no two-players-online-at-once requirement, and it slots into the offline-first / SwiftData architecture already chosen (§12) with only a thin backend for snapshot storage and matchmaking, not a full real-time multiplayer server.

- **Defense squad:** every player sets a 10-unit "Defense Squad" plus a deployment script (drag-set the order/rough timing they'd deploy in, capped at a handful of timed steps — not full manual play). This gets uploaded as a snapshot whenever the player changes it.
- **Attacking:** when a player queues into Rival Grounds, matchmaking pulls an opponent's snapshot and runs it through the *exact same PvE battle simulation* as a scripted stage — the opponent's Defense Squad deploys on their script, the attacker deploys live against it, on a lane with the same BU rules as everywhere else in the game. From the attacker's point of view this plays exactly like fighting a stage; the only difference is the "enemy" data came from another player's roster instead of level design.
- **Result:** the outcome (attacker win/loss, base HP remaining) is reported back and affects both players' ladder rank — the defender didn't have to be online for it.
- **Ranked ladder & seasons:** standard seasonal ladder (4-6 week seasons), rank tiers, season-end rewards. Losing your defense doesn't cost you anything material (no unit loss, no currency drain) — only ladder rank moves, keeping losses low-stakes and retention-friendly rather than punishing.
- **Rewards:** a dedicated PvP-only currency, **Glory**, earned from ladder rank and season-end payout. Glory buys **cosmetic-only** items — alternate color morphs, victory poses, arena banner frames — and small amounts of Evolution Catalysts. Glory is never sellable for or purchasable with Amber Shards, and nothing Glory buys affects PvE or PvP unit power. This is the load-bearing anti-P2W rule for the whole mode (see §14.3).

### 14.2 Tier 2 — Head-to-Head Clash (stretch goal, later phase)

The mechanically richer version, worth building once Tier 1 has proven the mode has an audience. Research changed two things about how this is scoped:

**What stays the same:** two players face off on a **single shared lane with both bases at opposite ends**, units walking toward each other and meeting in the middle. This is still the right idea — it's a direct extension of the existing lane/BU model (§4), and an Apex unit becomes a wall the opponent has to specifically answer with knockback or a swarm push, which is the one genuinely new tactical wrinkle PvP adds that PvE doesn't produce.

**What changed — the transport layer:** earlier drafts of this doc assumed Tier 2 needs "a real server-authoritative netcode stack," implying custom backend infrastructure. That's true for a Clash Royale-scale live-service, but Clash Royale's actual architecture is a *deterministic lockstep simulation* — both clients run bitwise-identical fixed-point simulations and the server only relays inputs, which demands strict floating-point-free determinism throughout the whole battle sim. Retrofitting that level of rigor onto RoarFare's existing SpriteKit sim (§12, currently a normal float-based simulation) would be a substantial rewrite, not a mode addition, and is the kind of engineering effort dedicated netcode teams take on — not a reasonable ask for a Claude+Xcode-built title. Two changes follow from that:

1. **Use GameKit (`GKMatch`), not a custom server, for the transport.** Apple's own real-time-multiplayer framework handles matchmaking and peer relay natively in Swift with no backend to stand up — `GKMatchmakerView` covers 2-player matchmaking directly, and `match.sendData(toAllPlayers:)` covers state sync. This removes the "we need to build server infrastructure" cost entirely for Tier 2's transport layer; it does **not** remove the determinism problem below.
2. **Default to periodic authoritative state sync, not lockstep-of-inputs.** Instead of chasing Clash Royale's bitwise-deterministic lockstep (fragile without a dedicated netcode discipline — any float drift desyncs the match), have one device act as the authoritative simulator for that match and broadcast periodic position/HP state snapshots (not raw inputs) over GameKit's relay; the other device renders from the latest snapshot. This tolerates minor timing jitter instead of requiring perfect determinism, at the cost of a bit more bandwidth — the right trade for a small team's actual capacity. **Caveat:** GameKit matches are peer-to-peer with no neutral third-party server validating outcomes, so a modified client on the authoritative side could misreport state; acceptable for a casual/ranked-lite launch of this mode, but if Rival Grounds Tier 2 ever becomes a serious competitive/esports-adjacent mode, that's the point to move the authoritative role to a real backend service instead of a player's device.
3. **Lower-risk structural alternative, worth strongly considering as the actual v1 of Tier 2 instead of continuous real-time:** Plants vs. Zombies Heroes — the closest existing precedent to "a Battle-Cats-style lane game with real PvP" — doesn't run continuous real-time simulation at all. It structures each match as discrete rounds (both players commit their plays for the round, then the round resolves simultaneously), which sidesteps the determinism/lockstep problem completely since nothing needs frame-perfect sync — only the round's outcome needs to match. **Recommendation: build Tier 2 as simultaneous-round Clash first** (both players get a short deploy window each round; the round then plays out through the existing lane sim exactly like a PvE stage tick, broadcast via GameKit once resolved; repeat until a base falls) rather than continuous real-time. It keeps the "shared lane, meet in the middle" tactical identity intact, and only upgrade to true continuous real-time later if the round-based version proves the mode is worth the extra investment.
- Same Glory currency, same cosmetic-only reward rule as Tier 1.

### 14.3 Fairness Rules (non-negotiable, given the monetization design in `MONETIZATION.md`)

Everything in `MONETIZATION.md` is built around "no purchasable unit, no purchasable power" — PvP is the one mode where breaking that rule would be most damaging (a whale literally beating a free player in a head-to-head match reads very differently than a whale clearing PvE content faster). So:

- **Stat normalization in PvP context only:** unit stats used inside Rival Grounds are scaled to a common power cap per rarity tier (a Legendary at level 10 and a Legendary at max level both fight at the same normalized stat line in PvP), so unit *level* and *Specimen Mastery stacks* (`MONETIZATION.md` §3) — both of which spend gates or accelerates — don't translate into a PvP power advantage. Roster *breadth* (which units you own, which evolution branches you've unlocked) still matters and is still a legitimate progression flex; raw grind/spend does not.
- **No currency purchasable with real money affects PvP power.** Amber Shards buy gacha pulls and cosmetics; they never buy anything that normalizes differently inside Rival Grounds.
- **Matchmaking bracket is roster breadth, not account age or spend.** Prevents a new account with a lucky early pull from being farmed by, and separately prevents whales from being matched against players who simply haven't unlocked as many units yet.
