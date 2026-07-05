# RoarFare — Monetization & Gacha Economy Spec

Companion to `GAME_DESIGN.md` §7 (Fossil Dig) and §10 (Progression & Economy). This document is the actual buildable spec for the gacha system and its real-money purchases: currencies, SKUs, drop-rate math, App Store compliance requirements, and StoreKit implementation notes. Treat the compliance section as non-negotiable — it's Apple policy, not house style.

---

## 1. Currency Stack

| Currency | Type | Earned by | Spent on | Purchasable with real money? |
|---|---|---|---|---|
| **Amber** | Soft, in-stage | Passive accrual during battles | Deploying units mid-battle | No — never sell the in-battle currency directly, it would be pay-to-win at the moment-to-moment level |
| **Fossil Fragments** | Soft, meta | Stage clear rewards, daily login, achievements | Dig Site pulls, unit leveling | Indirectly — Amber Shards convert to Fragments, never sold as their own SKU (keeps the "free currency" legible as free) |
| **Evolution Catalysts** | Soft, biome-specific | Stage drops per biome | Evolving units past base form | No — must stay fully earnable, since gating evolution behind a paywall would read as pay-to-win on power, not just speed |
| **Amber Shards** | Premium/hard | Small trickle from stage-clear milestones, achievements, events; primary source is real-money purchase | Dig Site pulls (premium rate), cosmetic items, Fossil Pass, convert to Fossil Fragments | **Yes** — this is the only currency IAP sells directly |
| **Glory** | Soft, PvP-only | Rival Grounds ladder rank and season-end payout (see `GAME_DESIGN.md` §14) | Cosmetic-only items (color morphs, victory poses, arena frames) and small Evolution Catalyst amounts | **No, in either direction** — Glory cannot be bought with Amber Shards and Amber Shards cannot be bought with Glory. This firewall is deliberate: it's what keeps PvP power un-purchasable per §14.3 |

Design rule: every currency must have a visible, if slow, free-to-earn path. A currency that is 100% purchase-only fails App Store review scrutiny in some regions and is bad practice regardless.

---

## 2. IAP Catalog

All prices below use Apple's standard price-tier increments as placeholders — final pricing should be set in App Store Connect against current tier tables, not hardcoded into the client.

### 2.1 Consumable — Amber Shard packs

| Product ID | Contents | Indicative price | Notes |
|---|---|---|---|
| `shards_small` | 300 Amber Shards | $1.99 | Low-friction first purchase |
| `shards_medium` | 1,650 Shards (10% bonus) | $9.99 | |
| `shards_large` | 3,600 Shards (20% bonus) | $19.99 | |
| `shards_mega` | 9,900 Shards (32% bonus) | $49.99 | |
| `shards_whale` | 21,000 Shards (40% bonus) | $99.99 | Cap the catalog here — do not exceed Apple's top consumable tier games commonly use without strong justification |

### 2.2 Consumable — first-purchase / value bundles

- `starter_pack` (one-time, non-consumable so it can't be rebought, but delivers consumable contents): heavily discounted bundle (e.g., 1,000 Shards + a guaranteed Epic unit + Fragments) offered once to new accounts. This is the standard gacha "$0.99 starter deal" — high conversion, low commitment, and it should be flagged clearly as one-time in the UI so players don't feel baited when it disappears.
- `biome_pass_bundle` (consumable, per-biome): a themed bundle tied to a specific Dig Site rotation (Shards + that biome's Evolution Catalysts). Rotates with the banner, same cadence as banner rotation in §3.

### 2.3 Non-consumable

- `remove_ads` (if the base game runs any ads/interstitials at all — optional; many gacha games skip ads entirely in favor of pure IAP+gacha, which is the cleaner model and recommended here to avoid stacking two monetization systems that fight each other for player goodwill).

### 2.4 Auto-renewable subscription

- `fossil_pass_monthly` (~$4.99/mo): grants a daily Fossil Fragment stipend, a small daily Amber Shard trickle, and access to a "Dig Pass" reward track (free track + paid track, battle-pass structure) that pays out Evolution Catalysts and cosmetic frames as players clear stages during the month. This is the highest-LTV, most player-friendly SKU in most gacha economies (it rewards continued play rather than pure luck) and should be the flagship offer, not an afterthought.

**Guardrail:** no SKU should let a player directly purchase a specific named unit outright (e.g., "Buy 1 T. Rex for $9.99"). Everything money-based must route through either the gacha pool (chance) or the pass/pity track (guaranteed but earned through play + time). Direct unit sales collapse the entire collection fantasy and invite "pay to auto-win" perception.

**Second guardrail (PvP-specific):** Rival Grounds cosmetics (color morphs, victory poses, arena frames) are earned only through Glory (`GAME_DESIGN.md` §14) and are never sold as a direct IAP SKU, even though they're purely cosmetic. Competitive-mode prestige items being earn-only (not purchasable at any price) is what keeps a ranked ladder feeling like a ladder rather than a storefront — the same logic ranked cosmetics follow in most competitive live-service games.

---

## 3. Gacha Mechanics (Dig Site pulls)

- **Pull cost:** 150 Fossil Fragments per single pull (or 1,350 for a 10-pull, a 10% discount vs. paying per-single — standard genre convention that rewards batch-pulling without being predatory).
- **Pity system (hard requirement, not optional):**
  - *Soft pity:* Legendary drop rate ramps upward starting at pull 75 within a Dig Site's counter.
  - *Hard pity:* guaranteed Legendary by pull 90 (counter persists across sessions, resets only on a hard-pity trigger, not on banner rotation). **This was revised down from an earlier draft's pull-200 hard pity** — genre benchmarking (§7) shows ~90-100 pulls is the player-expected ceiling for a top-rarity guarantee (Genshin Impact/Honkai Star Rail sit at 90; Arknights' effective 6-star rate is even friendlier, averaging 35-40 pulls). A 200-pull hard pity would read as unusually stingy against that baseline and risks reputational damage before RoarFare even has a player base to defend it.
  - *Epic soft pity:* ramps from pull 21, guaranteed by pull 30 (unchanged — this tier was already in a reasonable range).
  - *Rate-up banners:* limited-time Dig Sites can feature a rate-up unit; missing the rate-up unit on a hard-pity Legendary should guarantee the rate-up unit specifically on the player's *next* hard pity within that banner (standard "guaranteed after one miss" convention) — prevents a player from hard-pitying twice into off-banner units, which is the single most common source of gacha-related player anger.
- **Guaranteed-rarity ticket ("Amber-Sealed Specimen"):** a discrete item, separate from the pull-counter pity above, that instantly resolves to a random Legendary-tier unit (never a specific named one — see the no-direct-unit-sale guardrail in §2.4). Earned from stage milestones, event rewards, and rarely as a bonus in premium bundles; this is RoarFare's equivalent of Battle Cats' Platinum/Legend Ticket, which is one of that game's most well-liked mechanics precisely because it's an earnable, tradeable-feeling "skip the RNG floor" item rather than a pay-only shortcut.
- **Displayed odds:** every rarity tier's drop rate, per Dig Site, must be shown in-app before the player spends currency (a dedicated "Rates" screen linked directly from the pull button, not buried in settings). This is required, not a nice-to-have — see §4.

### 3.1 Duplicate Handling — the Copy Ladder

Every unit has a **copy ladder** that's the same shape regardless of rarity, but only pays out mastery past a certain point. The design goal: no duplicate is ever a dead pull, and the most valuable duplicate reward ties directly into RoarFare's actual differentiator (branching evolution, `GAME_DESIGN.md` §5) rather than being a generic imported stat-stick system.

| Copy # | What it does |
|---|---|
| **1st copy** | Unlocks the unit into your roster at base form — this is the only copy that matters for raw collection-completion tracking (Fossil Record, `GAME_DESIGN.md` §13). |
| **2nd copy** | Unlocks the ability to evolve a *second instance* of the unit down the **alternate evolution branch**. `GAME_DESIGN.md` §5 already establishes that branching evolutions are one-branch-per-deployed-copy — this is the mechanic that makes a duplicate concretely useful even to a player who doesn't care about numeric stat bumps: it's the only way to field both the "Herd Caller" and "Skull-Crest Rammer" version of the same Parasaurolophus in one squad. It still costs a full squad slot like any other unit, so running both branches is a real 10-slot budget decision, not a free bonus — duplicate value here is a build-expression unlock, not a power spike. |
| **3rd-7th copy** (Epic/Legendary only) | Each feeds one **Specimen Mastery** stack (capped at 5), a small permanent stat bonus (~+2%/stack) to that specific unit — a refinement, not a tier jump. Reserved for Epic/Legendary because those are the units players actually chase multiples of; see below for what happens to extra Common/Rare copies instead. This is the same "constellation/eidolon" dupe-value pattern that's become standard in modern gacha games for giving high-spend players a reason to keep pulling favorites they already own. |
| **3rd+ copy of Common/Rare, or 8th+ copy of Epic/Legendary** | Auto-converts to Fossil Fragments (a partial pull-cost refund) plus a fixed amount of that unit's Evolution Catalyst. Never a dead, valueless pull, but no further mastery accrues once the cap is hit. |

**PvP interaction:** the alternate-branch unlock (copy 2) is a roster-breadth/build-expression choice and is *not* normalized away in Rival Grounds (`GAME_DESIGN.md` §14.3) — owning and fielding both branches is a legitimate collection flex there. Specimen Mastery's numeric stat stacks *are* normalized away in PvP, same as unit level, since that's the raw grind/spend axis §14.3 is specifically designed to keep out of competitive power.

**UI implication:** the collection/roster screen should show each unit's copy-ladder progress (current copy count, mastery stacks filled, whether the alternate branch is unlocked) directly on its museum-placard card (§6 of the Art Bible) — this is exactly the kind of "collection completion" progress tracking that made Battle Cats' Cat Guide a strong retention hook (`GAME_DESIGN.md` §13), so it should be visible at a glance, not buried in a stats submenu.

---

## 4. App Store & Regional Legal Compliance

### 4.1 App Store Compliance Requirements

These are Apple policy obligations for any app offering randomized virtual-item purchases (loot boxes), which the Fossil Dig system is:

1. **Disclosed odds (App Store Review Guideline 3.1.1):** Apps offering "loot boxes" or other mechanisms that provide randomized virtual items must disclose the odds of receiving each item type to customers prior to purchase. RoarFare's Dig Site pull screen must show per-rarity percentages before the player confirms a spend — plan this as a first-class screen, not a legal-text afterthought.
2. **Age rating implications:** simulated-gambling mechanics (loot boxes) typically push the App Store age rating up (often to 17+) depending on current App Store Connect questionnaire answers — factor this into App Store Connect's age-rating survey at submission time; don't assume a "for kids" rating is available if the gacha system ships as designed.
3. **Parental controls / Ask to Buy:** since this is a title likely to attract younger players (dinosaurs, cute art style per the Art Bible), Apple's "Ask to Buy" family-sharing flow will commonly gate purchases for minors — this is Apple-side behavior the app doesn't need to implement, but purchase-confirmation UI should be designed assuming a parent may be interrupting the flow.
4. **Spend confirmation:** any purchase above a moderate threshold (e.g., the `shards_mega`/`shards_whale` tiers) should show a native confirmation step restating price and contents — reduces both accidental-purchase support tickets and the appearance of dark-pattern design.
5. **No purchase-required progression:** every stage and every unit's *base* form must be reachable through free-to-earn currency alone, even if slowly. Design the free Fragment/Catalyst drip rates in §10 of the design doc so a free player can clear the full campaign, just slower than a paying one.
6. **Restore purchases:** the non-consumable (`remove_ads`) and the subscription must support "Restore Purchases" per App Store requirements — build this into account/settings UI from day one, not retrofitted later.

### 4.2 Regional Legal Landscape (checked directly, not just referenced in passing)

App Store policy is necessary but not sufficient — loot-box law varies sharply by country and Apple's review doesn't cover it. Researched the current state per market:

- **Belgium — treat as a hard no-go, not a design constraint.** Belgium's Gaming Commission classifies *any* paid loot box as illegal gambling, with real criminal exposure (fines up to €800,000, potential prison terms for non-compliant publishers) — several major titles (Lost Ark, Diablo Immortal) have been pulled from the Belgian market over exactly this. Enforcement has reportedly been inconsistent (some pity-system games still operate there in practice), but "enforcement has been spotty" is not a foundation to build a monetization strategy on. **Recommendation: geo-block Belgium from the storefront at launch** rather than trying to design a compliant variant — this is the standard industry response and far cheaper than the alternative (a loot-box-free regional build).
- **Netherlands — narrower risk than Belgium.** Dutch courts have found that loot boxes are only treated as gambling when their contents have real-world market value and can be traded/sold outside the game (the EA case was reversed on exactly this reasoning). Since RoarFare's items are account-bound with no secondary market, this is lower risk than Belgium, but worth re-confirming at launch since Dutch enforcement has moved before.
- **EU-wide — a new concrete rule takes effect June 2026:** any game containing paid randomized items (loot boxes, gacha, card packs) receives a **minimum PEGI 16 rating**, regardless of the game's actual content. This directly contradicts the "cute dinosaur game" positioning the Art Bible leans into — RoarFare's actual EU storefront age rating will be 16+ once the Dig Site ships with real-money pulls, not the all-ages rating the art style would otherwise suggest. Plan store listing/marketing expectations around this now rather than being surprised by it at submission. A broader EU Digital Fairness Act (harmonizing loot-box rules union-wide) has been anticipated but wasn't confirmed as finalized as of this research pass — worth re-checking closer to launch.
- **Japan — the specific mechanic to avoid is "kompu gacha" (complete gacha).** Illegal since 2012 under the Act against Unjustifiable Premiums and Misleading Representations: a scheme where players must assemble a themed *set* of randomly-obtained items to unlock a separate, more valuable prize. Standard single/multi-pull gacha (what RoarFare's Dig Site already is) remains legal with disclosed odds. **This is directly relevant to the Fossil Record / collection-completion bonus idea from `GAME_DESIGN.md`'s genre-alignment pass — keep it structured as small additive per-unit rewards for each new discovery, never as a single large "grand prize" contingent on assembling a specific randomly-obtained subset.** That's already the more natural design anyway, so no rework needed, just a guardrail to keep in mind if the Fossil Record system gets built out further.
- **China — informational only, not actionable for now.** China's requirements go well beyond odds disclosure: a public 90-day log of loot box outcomes, daily pull limits (30 singles/day, 3 ten-pulls/day, 50 total/day), and critically, a ban on any item being loot-box-*exclusive* — every obtainable item needs some non-gacha acquisition path. This would require real changes to the banner-exclusive-unit convention RoarFare otherwise follows (§3). In practice, shipping in China also requires separate publishing approval and a local publisher partnership regardless of gacha design, so treat China as out of scope for an indie/solo build rather than a design target — revisit only if a Chinese publishing partner is actually in the picture.
- **United States — no federal loot-box law, but real enforcement risk via FTC/COPPA, not gambling law.** There's no blanket US ban, but the FTC has pursued loot-box mechanics as deceptive/unfair practices and COPPA violations when minors are involved — Cognosphere (Genshin Impact's publisher) was hit with a real settlement on exactly this basis. Given the Art Bible's cute, kid-appealing tone, this is RoarFare's most concrete real-world legal precedent, more so than the loot-box-specific state bills (NY, HI, WA, IN) that have been proposed but not enacted. Reinforces §4.1 point 3 above: don't treat "Ask to Buy" as sufficient — avoid any marketing or UX that could read as targeting under-13 players toward a paid pull, and keep spend-confirmation flows unambiguous regardless of who's holding the device.

**Net scope recommendation:** ship broadly in the US/EU/UK/rest-of-world at launch, geo-block Belgium, keep the already-planned disclosed-odds-and-pity design (which is what keeps Japan and most of the EU/US legal), and don't pursue China unless a local publisher is actually attached to the project.

---

## 5. StoreKit Implementation Notes (Swift / Xcode)

- **Use StoreKit 2**, not the older StoreKit 1 APIs — it gives async/await `Transaction` and `Product` APIs, built-in signed JWS transaction verification, and simpler subscription-status handling, all of which matter for a title with both consumables and a subscription.
- **Product configuration:** define all product IDs (§2) in App Store Connect, and mirror them in a local `Products.storekit` configuration file for Xcode's StoreKit Testing framework — this lets the gacha/purchase flow be fully testable in the simulator without sandbox App Store accounts during development.
- **Transaction verification:** always check `VerificationResult` on each `Transaction` before granting currency — never grant Amber Shards optimistically before verification succeeds, to avoid a client-side exploit path.
- **Server vs. client-authoritative pulls:** for MVP, client-authoritative pull resolution (weighted RNG resolved on-device, seeded and logged) is acceptable given no PvP/leaderboard stakes ride on gacha outcomes; if RoarFare later adds competitive leaderboards or trading, migrate pull resolution to a server to prevent client-side manipulation of drop rates.
- **Subscription status:** listen to `Transaction.updates` for the `fossil_pass_monthly` subscription so lapses/renewals update the Dig Pass track state immediately, including across app relaunches and other devices signed into the same Apple ID.
- **Currency ledger:** keep Amber Shards / Fossil Fragments / Evolution Catalysts balances in local persistence (SwiftData, per the design doc's tech notes) but treat consumable-IAP-driven credits as an audit trail (store a log of granted transactions keyed by StoreKit transaction ID) so a failed/refunded transaction can be reconciled rather than silently duplicating currency on a retry.
- **Sandbox testing:** test the full pity-counter and rate-up-guarantee logic (§3) against sandbox purchases before submission — pity bugs (e.g., counter resetting on app relaunch) are a common review-rejection and player-trust failure mode.

---

## 6. Metrics to Track Post-Launch (design intent, not implementation)

Even at MVP, instrument these from day one so tuning isn't a guessing game later:

- Pull-to-first-Legendary distribution (validates pity math matches intended odds in practice).
- Free vs. paying player campaign-completion rate (validates §4.5's "completable without spend" requirement is actually true, not just true on paper).
- Starter-pack conversion rate and Dig Pass renewal rate (the two SKUs expected to carry most of LTV per §2).

---

## 7. Genre Benchmarking (why the numbers above are what they are)

Checked this spec against current tower-defense/hero-collector gacha norms (Battle Cats itself, Arknights, and the broader Genshin/Star Rail-style gacha mainstream) before finalizing. Findings and what changed as a result:

| Finding | Source pattern | RoarFare's response |
|---|---|---|
| Top-rarity hard pity clusters around 90-100 pulls industry-wide; Arknights is even friendlier (~35-40 pulls per 6-star average) and is explicitly praised for it | Genshin Impact/Star Rail 90-pull pity; Arknights' low pull-pressure design is cited as a retention/goodwill advantage | Cut Legendary hard pity from an initial 200-pull draft down to 90 (§3) — 200 would have read as unusually stingy vs. the baseline players already carry from other games |
| Duplicate pulls of an already-owned top-tier unit are a major spend driver when they grant a small permanent refinement (Genshin Constellations, Star Rail Eidolons), not just currency | Cross-genre gacha standard | Added the Specimen Mastery dupe track (§3) so Epic/Legendary dupes stay exciting past the first pull, instead of just converting to currency |
| Battle Cats' Platinum/Legend Tickets (an earnable item that outright guarantees a top-tier unit) are consistently cited as one of its most player-liked mechanics | Battle Cats Cat Capsule system | Added the Amber-Sealed Specimen ticket (§3) as a discrete earnable guarantee, separate from the pull-counter pity |
| Battle passes/subscriptions now appear in roughly 60%+ of live-service gacha titles and are considered the most player-friendly high-LTV SKU (rewards play, not luck) | 2026 mobile monetization market surveys | Already aligned — `fossil_pass_monthly` (§2.4) was designed this way from the first draft |
| Seasonal/limited-time events rotating every 2-4 weeks are near-universal (46-59% adoption) and are the primary spend trigger alongside banners | Same surveys | Already aligned — Banner Site rotation (Design Doc §7) and Extinction Events (Design Doc §8) already run on this cadence |
| Disclosed odds, visible pity counters, and "ethical monetization" framing are an explicit 2026 industry trend, not just an App Store requirement | Same surveys | Already aligned and over-indexed here on purpose (§4) — being ahead of the compliance curve is a differentiator, not just a checkbox |
| A "borrow a friend's/stranger's high-rarity unit for one attempt" support system (Arknights' Support Unit, Fire Emblem Heroes' friend units) is a widely-loved feature that flattens early-game difficulty spikes and adds a social/collection-flex hook | Arknights design analysis | **Not yet in RoarFare's spec.** Recommended as a post-MVP addition — a "Guest Dino" slot that lets a player borrow one friend/random-player unit per stage attempt at zero cost. Doesn't fit the MVP cut (Design Doc §11) but should be on the near-term roadmap; it's low mechanical risk (read-only borrow, no trading/economy implications) and directly addresses new-player wall frustration |
| Crossover/collab events (licensed or in-universe) are one of the single biggest revenue and press-attention spikes for this genre — Battle Cats in particular has built years of retention on them | Battle Cats collab history; genre-wide collab pattern | RoarFare is an original IP so day-one licensed collabs aren't available, but the Dig Site banner system (§3, Design Doc §7) is generic enough to host a themed "guest era" event later (either an in-universe crossover cast or an eventual licensed collab) — worth keeping in mind as a live-ops lever, not a launch requirement |
| ~55% of new titles ship some multiplayer/PvP feature | 2026 market surveys | **Deliberately not adopted** — Battle Cats itself has no PvP and stays successful without it; adding PvP would mean designing around competitive balance (direct tension with the collection-power-fantasy design in the Design Doc), which is out of scope for RoarFare's MVP and arguably its whole first version |

**Net effect on the two other docs:** no changes needed in `ART_BIBLE.md` — none of this research touches tone/silhouette/palette. `GAME_DESIGN.md` gets one addition (§13 below) covering the two genre-standard features this spec didn't originally have room for (Guest Dino support borrowing, collab-ready banner framing) plus an explicit call-out of the PvP omission as a choice rather than an oversight.
