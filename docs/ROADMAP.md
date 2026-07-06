# RoarFare — Roadmap to Ship

The end goal: RoarFare live on the App Store as a working lane tower-offense game with the systems in `GAME_DESIGN.md`, the look in `ART_BIBLE.md`, and the economy in `MONETIZATION.md`. This doc is the step-by-step path from where the repo stands today to that goal. Each phase has a goal, concrete steps, and an exit criterion — don't move to the next phase until the current one's exit criterion is actually met, not just "mostly done."

Model guidance per phase is included since it matters for cost/quality — see the chat answer this doc followed for the full reasoning; short version: Sonnet for the great majority of it, Opus for a handful of named high-stakes checkpoints, Fable only for the narrative-voice tasks explicitly marked.

---

## Phase 0 — Get the code onto a Mac and compiling — ✅ DONE

Built clean and the full test suite passed, all green, first try. Every hand-traced piece of logic in this repo — BU-cap math, knockback, the attack-speed aura, the first-hit bonus, the Era counter table — held up against a real compiler and test runner for the first time. This is the first genuinely verified milestone in the project; everything before this was reasoned-through but unconfirmed.

**Goal (met):** confirm `RoarFareCore` actually builds and its test suite actually passes. Everything in this repo has been hand-traced and reviewed twice, but never compiled — this environment has no Swift toolchain and no way to get one (network policy blocks `download.swift.org`).

**Steps:**
1. Pull the `claude/dino-tower-defense-design-34ll7v` branch onto a Mac with Xcode installed.
2. Open `Package.swift` directly in Xcode (`File > Open`).
3. Build the `RoarFareCore` target. Fix whatever the compiler flags — expect a handful of small issues; none of the logic has been machine-verified yet.
4. Run the test suite (`Cmd+U`). All tests in `Tests/RoarFareCoreTests/` should pass; if any fail, that's a real bug this hand-tracing missed, not a flaky test — fix the code, not the assertion, unless the assertion itself is provably wrong.

**Exit criterion:** `swift test` (or Xcode's test runner) is green.

**Model:** Sonnet — you'll be pasting compiler errors back into a session; this is exactly the debugging work Sonnet should do. Save Opus for if something is *conceptually* wrong (a design flaw the compiler surfaces), not for routine type errors.

---

## Phase 1 — Wrap the core in a playable vertical slice

**Status: done, and past its original exit criterion.** `AppSource/RoarFareGame.swift` is a real, running app confirmed building and launching in the Simulator — not via the original plan (a separate `RoarFareCore` package dependency), but as a single self-contained file, because the package-dependency + multi-file-target setup kept producing broken Xcode project states (stale frameworks, missing `@main`, signing confusion) that were faster to route around than debug live, file by file, over chat. That workaround is documented in the README's "Playable app" section.

**Steps (kept for history — all done):**
1. ~~Create a new Xcode iOS App target... add `RoarFareCore` as a local package dependency.~~ Superseded — single self-contained file instead, no package dependency.
2. Build a single `SKScene` that renders `Lane` state — done.
3. Wire the SpriteKit update loop to call `Lane.tick(deltaTime:)` every frame — done.
4. Deploy UI gated by an accruing Amber counter — done, and extended: every evolution branch is now its own deploy button, and buttons grey out when unaffordable.
5. Enemy AI — done, and fixed past the original plan: initially spawned a uniformly random unit (including the most expensive one) on a flat timer with zero cost check, which would have made the game unwinnable. Now the enemy has its own Amber-style economy and only deploys what it can afford.
6. Win/lose detection and end screen — done, plus a "Play Again" button (`BattleScene.reset()`) that wasn't in the original plan but was an obvious gap once actually playtestable.

**Exit criterion (met):** the game builds and runs in the Simulator. **Not yet actually playtested against real gameplay feel** — the numbers (walk speed, Amber income, enemy economy pace) are reasoned-through guesses, not tuned from play. That's the honest next step before calling Phase 1 fully closed.

**Model:** Sonnet for all of it — this phase is exactly why: real Xcode errors, read from screenshots, needed direct debugging judgment, not autonomous execution.

---

## Phase 2 — Close the three known gaps

**Status: done in code, not yet verified by a compiler.** All three were built in a follow-up pass (`Ability.swift`, `EraCounters.swift`, and position-aware `currentBU` in `Lane.swift`), with new tests hand-traced the same way as everything else in this repo. What actually landed:

1. **Abilities engine — done, intentionally narrow.** `Ability` covers exactly two shapes: `.attackSpeedAura(range:attackIntervalMultiplier:)` (Herd Caller) and `.firstHitBonus(damageMultiplier:)` (Ambush Striker), resolved inside `Lane.tick()`. It's still a small, closed set of ability *shapes*, not a general scripting system — the next new ability type still means adding a new `Ability` case and wiring it in, not just JSON. Multiple overlapping auras don't stack (strongest wins) — a deliberate simplification.
2. **Position-aware BU tracking — done, with a specific chosen definition.** "Engaged at the front" was defined as: within `Lane.frontlineEngagementRange` (2.0) of that side's most-advanced alive unit. A knocked-back unit (shove distance 3.0, deliberately larger than the engagement range) reliably drops out of the BU count even though it's still alive. A side with only one unit is trivially its own front tip, so a lone unit always counts — the mechanic only matters once a side has multiple units and one gets separated from the pack.
3. **Era trait/counter web — a first slice only, not the full §3 web.** `EraCounters.damageMultiplier(attacker:defender:)` models just the two purely-numeric relationships from §3 (Ice Age vs. Triassic, Jurassic vs. Cretaceous) as flat 1.25x damage multipliers. The rest of §3 (armor/mitigation, ranged-kites-slow, swarm-surrounds-single-target, Sky vs. Burrower) either depends on stats/traits that don't exist yet (armor, enemy traits) or is emergent behavior from existing range/attack-speed stats rather than a table entry — deliberately not attempted in this pass. Building out the rest is still real, separate work.

**Exit criterion (unchanged, still pending):** playtesting the Phase 1 slice, once it exists, should feel different because of these — aura visibly speeds up allies, a knocked-back unit visibly reopens deploy room, an Ice-Age unit visibly hits Triassic swarms harder. That can't actually be confirmed until Phase 1's vertical slice exists to play.

**Model:** this was done on Sonnet without an Opus architecture-review checkpoint first, since it happened in the same environment that can't compile Swift at all — an extra reasoning pass wasn't going to change the fact that none of it has been machine-verified yet. **Do the Opus review retroactively once Phase 0/1 are done and this code actually compiles and runs** — specifically on the `Ability` shape (does it generalize to the ~10-20 more abilities the full roster will need) and the `frontlineEngagementRange`/`knockbackDistance` numbers (do they feel right in actual play, not just in a hand-traced test).

---

## Phase 3 — MVP content complete

Follow `GAME_DESIGN.md` §11 exactly; it was written to be the minimum that proves the game isn't a reskin:

1. Expand from 8 to a full first-biome roster if needed, all still hand-authored (not yet using any content-generation shortcuts).
2. Build one full biome's worth of stages (8-10) using Tier 1-2 enemies (Rival Dinosaurs, Burrowers) — this is where `Era` and trait-counters from Phase 2 actually get exercised across a real difficulty curve.
3. Build the single Dig Site: the pull screen, the odds-disclosure screen (non-negotiable per `MONETIZATION.md` §4.1), the pity counters, and the Copy Ladder duplicate system (`MONETIZATION.md` §3.1).
4. Build the Fossil Record (`GAME_DESIGN.md` §13) — cheap, high-retention, do it now rather than deferring.

**Exit criterion:** a new player can install the build, play through the first biome, pull on the Dig Site, and see their collection grow — the full MVP loop end to end, no placeholder screens.

**Model:** Sonnet for the build. If stage difficulty tuning feels off and you're not sure why, that's a good Opus moment (balance reasoning across many interacting stats benefits from deeper analysis) — but don't reach for it before you've actually playtested and have a concrete question.

---

## Phase 4 — Monetization integration

Only start this once Phase 3's loop is provably fun without money involved — building payment rails around a loop that isn't fun yet is wasted work.

1. Set up all product IDs in App Store Connect per `MONETIZATION.md` §2's catalog.
2. Implement StoreKit 2 per §5: `Products.storekit` config for local testing, transaction verification, the subscription status listener for `fossil_pass_monthly`, the currency ledger with transaction-ID-keyed audit trail.
3. Wire the odds-disclosure screen, spend confirmations, and Restore Purchases flow — these are Apple review requirements, not optional polish (§4.1).
4. Sandbox-test the full pity/rate-up logic against real sandbox purchases (§5's explicit call-out: pity counter bugs are a common rejection reason).
5. Geo-block Belgium per §4.2's legal recommendation before this ever reaches a real App Store Connect build.

**Exit criterion:** a sandbox purchase correctly grants currency, the pity counter survives an app relaunch, and Restore Purchases actually restores.

**Model:** Sonnet for implementation. **Opus checkpoint recommended here too** — a focused security/correctness review of the transaction-verification and currency-ledger code specifically, before it's anywhere near a build with real payment processing attached. This is real money and real App Store review risk; the extra reasoning pass is worth it exactly once, right before this phase closes.

---

## Phase 5 — Art production pass

Everything up to now has run on placeholder shapes. Now execute `ART_BIBLE.md` for real:

1. Lock the chibi tone (§1) with a first real unit — probably the T. Rex, since it's the Legendary/Apex flagship — and get sign-off on it before batch-producing the rest of the roster, since every subsequent unit is judged against this one.
2. Produce the Era palettes (§3.1) and rarity frame treatments (§3.2) as reusable assets/shaders, not one-off per-unit choices.
3. Produce the Fossil Egg pull object (§6.1) in all four rarity shell treatments plus the amber-encased ticket variant.
4. Produce biome environment art (§5) for the one MVP biome.
5. Replace every placeholder sprite from Phase 1 with real art.

**Exit criterion:** the Phase 3 build, replayed, looks like RoarFare instead of programmer art.

**Model:** this is the one phase where Fable earns a real role — use it for supporting narrative-voice deliverables that ride alongside the art (Fossil Record entry bios per unit, in-app copy for the Dig Site/biome names, App Store listing copy). The actual visual asset production itself isn't a Claude-model question at all — that's an art tool/pipeline decision (Xcode/SpriteKit assets, whatever image tooling you use), not something to route through model selection.

---

## Phase 6 — QA and submission

1. Full playtest pass: golden path (a new player's first hour) and edge cases (what happens at 0 Amber, at a full frontline, mid-knockback, on a failed purchase, on app relaunch mid-pity-counter).
2. Confirm the App Store age-rating questionnaire reflects the loot-box mechanics honestly (`MONETIZATION.md` §4.1 item 2, §4.2's PEGI 16 note for EU).
3. Submit to App Store Connect.

**Exit criterion:** approved and live.

**Model:** Sonnet for fixing whatever QA turns up.

---

## Phase 7 — Post-launch: the deferred list, in priority order

Everything explicitly deferred across the design docs, roughly in the order it's worth tackling:

1. **Guest Dino** (support-borrow system, `GAME_DESIGN.md` §13) — highest genre-validated retention value for the engineering cost, and it's the natural first thing to build once a backend exists at all (which Phase 4's StoreKit/App Store Connect work implies some server-side presence, even if minimal).
2. **Pack Hunting synergies** (§6) and **Extinction Events** (§8) — these deepen the existing loop rather than requiring new infrastructure.
3. **Rival Grounds Tier 1** (async PvP ladder, §14.1) — needs the backend from Guest Dino anyway (snapshot storage), so sequence it after that lands.
4. **Marine/Sky sub-eras** and the remaining enemy tiers (§9) — expand content breadth once the core loop has real player data to tune against.
5. **Rival Grounds Tier 2** (real-time Clash, §14.2) and **collab-ready banner events** (§13) — biggest remaining engineering/business lifts; only worth it once the game has an actual live player base to justify them.

**Model:** Sonnet throughout, same Opus-for-checkpoints pattern as above (an architecture review before Tier 2's netcode work is the next obvious candidate).

---

## Immediate next 3 actions, right now

1. **Start Phase 1** — create the Xcode iOS App target, add `RoarFareCore` as a local package dependency, and build the `SKScene` that renders `Lane` state. This is the phase most worth doing interactively (you driving Xcode, not code written blind), since it's the first point you'll actually feel whether BU-blocking and knockback are fun.
2. Keep committing and pushing as you go, even mid-phase — don't let a working Simulator build sit uncommitted.
3. Still don't start Phase 4 (monetization) or Phase 5 (art) early just because they feel more exciting than Phase 1 — build the playable loop first.
