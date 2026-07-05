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

---

## 3. Gacha Mechanics (Dig Site pulls)

- **Pull cost:** 150 Fossil Fragments per single pull (or 1,350 for a 10-pull, a 10% discount vs. paying per-single — standard genre convention that rewards batch-pulling without being predatory).
- **Pity system (hard requirement, not optional):**
  - *Soft pity:* Legendary drop rate ramps upward starting at pull 75 within a Dig Site's counter.
  - *Hard pity:* guaranteed Legendary by pull 90 (counter persists across sessions, resets only on a hard-pity trigger, not on banner rotation). **This was revised down from an earlier draft's pull-200 hard pity** — genre benchmarking (§7) shows ~90-100 pulls is the player-expected ceiling for a top-rarity guarantee (Genshin Impact/Honkai Star Rail sit at 90; Arknights' effective 6-star rate is even friendlier, averaging 35-40 pulls). A 200-pull hard pity would read as unusually stingy against that baseline and risks reputational damage before RoarFare even has a player base to defend it.
  - *Epic soft pity:* ramps from pull 21, guaranteed by pull 30 (unchanged — this tier was already in a reasonable range).
  - *Rate-up banners:* limited-time Dig Sites can feature a rate-up unit; missing the rate-up unit on a hard-pity Legendary should guarantee the rate-up unit specifically on the player's *next* hard pity within that banner (standard "guaranteed after one miss" convention) — prevents a player from hard-pitying twice into off-banner units, which is the single most common source of gacha-related player anger.
- **Guaranteed-rarity ticket ("Amber-Sealed Specimen"):** a discrete item, separate from the pull-counter pity above, that instantly resolves to a random Legendary-tier unit (never a specific named one — see the no-direct-unit-sale guardrail in §2.4). Earned from stage milestones, event rewards, and rarely as a bonus in premium bundles; this is RoarFare's equivalent of Battle Cats' Platinum/Legend Ticket, which is one of that game's most well-liked mechanics precisely because it's an earnable, tradeable-feeling "skip the RNG floor" item rather than a pay-only shortcut.
- **Duplicate handling — Specimen Mastery:** the *first* copy of any unit is what matters for the collection/roster; every duplicate beyond that feeds a per-unit **Mastery** track (capped at 5 stacks) that grants a small permanent stat bonus (roughly +2%/stack) to that specific unit, instead of just converting to currency. Common/Rare duplicates still auto-convert to Fossil Fragments + Evolution Catalyst as before (mastery is reserved for Epic/Legendary, where players actually care about owning multiples of a favorite). This mirrors the "constellation/eidolon" dupe-value pattern that's become the standard way modern gacha games give high-spend players a reason to keep pulling for units they already own, without it being a raw pay-to-win power spike (2%/stack is a refinement, not a tier jump).
- **Displayed odds:** every rarity tier's drop rate, per Dig Site, must be shown in-app before the player spends currency (a dedicated "Rates" screen linked directly from the pull button, not buried in settings). This is required, not a nice-to-have — see §4.

---

## 4. App Store Compliance Requirements

These are Apple policy obligations for any app offering randomized virtual-item purchases (loot boxes), which the Fossil Dig system is:

1. **Disclosed odds (App Store Review Guideline 3.1.1):** Apps offering "loot boxes" or other mechanisms that provide randomized virtual items must disclose the odds of receiving each item type to customers prior to purchase. RoarFare's Dig Site pull screen must show per-rarity percentages before the player confirms a spend — plan this as a first-class screen, not a legal-text afterthought.
2. **Age rating implications:** simulated-gambling mechanics (loot boxes) typically push the App Store age rating up (often to 17+) depending on current App Store Connect questionnaire answers — factor this into App Store Connect's age-rating survey at submission time; don't assume a "for kids" rating is available if the gacha system ships as designed.
3. **Parental controls / Ask to Buy:** since this is a title likely to attract younger players (dinosaurs, cute art style per the Art Bible), Apple's "Ask to Buy" family-sharing flow will commonly gate purchases for minors — this is Apple-side behavior the app doesn't need to implement, but purchase-confirmation UI should be designed assuming a parent may be interrupting the flow.
4. **Spend confirmation:** any purchase above a moderate threshold (e.g., the `shards_mega`/`shards_whale` tiers) should show a native confirmation step restating price and contents — reduces both accidental-purchase support tickets and the appearance of dark-pattern design.
5. **No purchase-required progression:** every stage and every unit's *base* form must be reachable through free-to-earn currency alone, even if slowly. Apple review (and most regional consumer-protection regimes for loot boxes — Belgium/Netherlands historically, Japan's kompu gacha rules, China's odds-publication law if RoarFare ever ships there) scrutinizes whether the game is playable/completable without spend. Design the free Fragment/Catalyst drip rates in §10 of the design doc so a free player can clear the full campaign, just slower than a paying one.
6. **Restore purchases:** the non-consumable (`remove_ads`) and the subscription must support "Restore Purchases" per App Store requirements — build this into account/settings UI from day one, not retrofitted later.

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
