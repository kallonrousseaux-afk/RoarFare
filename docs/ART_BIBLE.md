# RoarFare — Art Bible

Companion to `GAME_DESIGN.md`. This document defines the visual identity so that units, enemies, UI, and environments produced by different passes (or different people/tools) stay consistent.

---

## 1. Tone & Visual Direction

RoarFare needs one deliberate choice here, because "dinosaurs" pulls toward two opposite defaults and splitting the difference produces mush. **Recommendation: lean into Battle Cats' proven chibi-absurdist tone, applied to dinosaurs, rather than semi-realistic Jurassic-Park styling.**

Reasoning:
- Chibi-cute reads instantly at the small sprite sizes a lane-based tower-offense game actually renders units at (Battle Cats units are often <100px on screen mid-battle) — semi-realistic detail is wasted or muddy at that scale.
- Cute + absurd gives permission for gameplay silliness (a T. Rex doing a chibi stomp, a Triceratops with a party-hat evolved form) without fighting the player's expectation of realism.
- It's cheaper to produce at scale (100+ units) with a consistent small team or AI-assisted pipeline than photoreal creature design, which demands per-unit sculpting-level fidelity to not look uncanny.

This is a recommendation, not a lock — if the project later wants a "premium" semi-realistic reskin as a cosmetic pack, that's viable *after* the core cute style ships, not instead of it.

**Tone descriptors:** chunky, round, big-eyed, high-contrast, toylike, slightly bouncy in motion. Think "dinosaur toy chest" more than "nature documentary."

---

## 2. Silhouette & Proportion Rules

These rules exist so a unit is identifiable by silhouette alone at battle scale (no color, no detail) — this is the actual test every unit design must pass before it ships.

- **Head-to-body ratio:** oversized head (roughly 1:2.5 to 1:3 head-to-body, vs. realistic ~1:6-1:8) on all ground units. This is the single biggest lever for "cute" and must be applied uniformly or units will feel like they're from different games.
- **Limbs:** stubby, rounded, no visible claws-as-weapons on herbivores; predators get slightly more angular (but still rounded-tip) limbs to read as threat without going realistic-sharp.
- **Eyes:** large, forward-facing dot or oval eyes on all units regardless of real-world eye placement (yes, even Triceratops) — this is a deliberate design law, not an error, because forward-facing eyes read as "character" and side-facing eyes read as "background animal."
- **Size-class silhouette must match gameplay size class** (see Design Doc §4): a Tiny unit's silhouette should look small/quick even in a lineup with no scale reference; an Apex unit's silhouette must be immediately the widest/tallest thing on screen. Never let a gameplay-Large unit have a visually-slighter silhouette than a gameplay-Medium unit — the player uses silhouette to eyeball BU cost mid-battle.
- **Read-at-10px test:** every unit thumbnail must be distinguishable from its neighbors in the same Era when scaled down to a 32x32 icon. If two units are only distinguishable by a color swap, differentiate the silhouette further.

---

## 3. Color Language

### 3.1 Era palettes (primary identity signal)

Each Era gets a signature palette family. Era palette should be visible in a unit's dominant color even before checking its icon frame — this lets players "see" the rock-paper-scissors matchup at a glance during fast-paced battles.

| Era | Palette | Hex anchors | Mood |
|---|---|---|---|
| **Triassic** | Warm ochre / rust / sand | `#C77B3B` `#E3A857` `#7A4A2B` | Scrappy, early, sun-baked |
| **Jurassic** | Deep forest green / bark brown | `#2F5233` `#4C7A47` `#3B2A20` | Lush, dense, heavy |
| **Cretaceous** | Teal / clay-red / bone white | `#2E7D6B` `#B5533C` `#E8DCC4` | Varied, tactical, "peak diversity" |
| **Ice Age** | Ice blue / slate grey / white | `#6FA8C7` `#3E4C59` `#EDF3F7` | Cold, crisp, high-contrast |
| **Marine** | Deep ocean blue / seafoam | `#1B4965` `#5FA8D3` `#CAE9FF` | Cool, pressurized, alien |
| **Sky** | Dusty violet / cloud white | `#8074A8` `#B7ACD4` `#F4F1FA` | Light, airy, fast |

### 3.2 Rarity accents (frame/border only — never the unit's body color)

Rarity is signaled the way Battle Cats signals it: via card frame and a corner gem/glow, not by recoloring the creature itself (recoloring the creature would collide with the Era-palette signal above).

| Rarity | Frame treatment |
|---|---|
| Common | Plain grey-brown frame, no glow |
| Rare | Bronze frame, faint glow |
| Epic | Silver-teal frame, particle sparkle on card |
| Legendary | Gold/amber frame, animated glow + fossil-crack texture overlay |

### 3.3 Enemy factions (§9 of design doc) — distinct from player palettes on purpose

Enemy units must never be color-confusable with player units of the same Era, since players make split-second "friend or foe" reads mid-battle.

| Faction | Palette | Notes |
|---|---|---|
| Rival Dinosaurs | Desaturated version of matching player Era palette | Reads as "familiar but not yours" |
| Burrowers | Dull ochre-brown / dirt tones, matte (no shine) | Blend-into-ground read |
| Leviathans | Deep abyssal blue-black with bioluminescent teal accents | Marine-stage threat read |
| Swarmkind | High-saturation warning yellow-black banding | Insect/hazard signaling, deliberately "wasp" coded |
| Ashborn | Charcoal black base with glowing orange cracks | Volcanic threat, animated ember particles |
| The Mammal Ascendant | Muted neutral browns/greys, small scale, minimal ornamentation | Deliberately unglamorous — "small grey thing" undercutting the player's expectation of a climactic final-boss silhouette, which is itself the point (extinction sneaks up on you) |

### 3.4 UI palette

- **Base UI chrome:** warm off-white / bone (`#F4EEE2`) and dark umber (`#3B2A20`) — ties UI to the "fossil/museum" framing rather than a generic blue-grey game-UI default.
- **Positive/Amber currency:** amber-gold (`#E8A93B`), reinforcing the in-fiction "Amber" currency name.
- **Fossil Fragments currency:** bone-white with a subtle crack texture icon.
- **Danger/HP-low state:** standard red (`#D64545`) — don't get clever here, HP-low needs to read instantly.

---

## 4. Enemy Design Language (visual)

Beyond palette, enemies should be shape-differentiated from player units at the silhouette level, not just recolored player assets:

- Player units: rounded, soft, big-eyed (see §2).
- Enemy units: slightly more angular joints, smaller/narrower eyes or no visible eyes (Burrowers, Swarmkind), and asymmetric details (scars, chipped horns, mismatched spikes) — signals "wild/hostile" vs. the player roster's toy-like uniformity.
- Faction silhouette motifs: Leviathans are wide/low and horizontal; Swarmkind are small and clustered (read as a "mass" even at 2-3 on screen); Ashborn have jagged, crack-lit outlines; The Mammal Ascendant units are small, upright, and deliberately unthreatening-looking until their stat-adaptation mechanic reveals itself over a fight.

---

## 5. Environment / Biome Art

Environments are horizontal parallax backgrounds (standard for this genre) behind the lane. Each biome gets a 3-layer parallax treatment (far background, mid, lane-adjacent foreground dressing):

| Biome | Far layer | Mid layer | Foreground dressing |
|---|---|---|---|
| Desert Dig | Warm gradient sky, distant mesas | Sparse cycads, dune ridges | Sun-bleached bones, cracked earth |
| Arctic Dig | Pale blue-white sky, aurora hint | Snow-capped ridgelines | Ice crystals, frozen tufts of grass |
| Swamp Dig | Hazy green-grey sky | Dense fern canopy silhouettes | Standing water reflections, fallen logs |
| Coastal Dig | Sea-blue gradient, horizon line | Rock stacks, distant reef break | Tide pools, driftwood, shell debris |
| Volcanic Dig | Ash-red sky, smoke plumes | Lava-glow ridgelines | Cracked obsidian ground, ember particles |

Biome art should always leave the lane itself (the ground strip units walk on) in a consistent neutral value range across all biomes, so unit silhouettes never lose contrast against a busy background — this is a hard readability requirement, not a style suggestion.

---

## 6. UI/UX Style

- **Card/frame system:** museum-placard aesthetic — unit cards look like fossil ID plaques (bone-white card stock, small "specimen number" in corner, Era icon as a stamped seal) rather than generic glossy game-gacha cards. Reinforces the "you're a collector/paleontologist" fantasy without adding new mechanics.
- **Iconography:** flat, high-contrast, single-color-per-icon (currency icons, stat icons) so they stay legible at the small sizes mobile HUDs demand.
- **Typography:** a rounded, slightly heavy display face for headers (matches the chunky-toy unit style); a clean, high-legibility face for body/stat text — avoid any "cracked bone/fossil-textured" display fonts for body text, they fail at small sizes.
- **World map:** illustrated, semi-isometric biome nodes on a single connected path (not a grid) — mirrors Battle Cats' chapter-map convention, which works well for signaling "linear campaign with branching side content."

### 6.1 Dig Site Pull Object — the Fossil Egg

The single most-repeated asset in the game (every gacha pull shows it) should be a **dinosaur egg sitting in a small dirt/straw nest**, not a generic capsule or treasure chest — it's the one place the "digging up a fossil" fantasy and the moment-to-moment gacha loop are the same image.

- **Shape:** rounded but deliberately asymmetric/elongated (real theropod eggs aren't perfect ovals) — keeps it reading as organic rather than a painted-on egg shape over a generic capsule.
- **Shell surface:** a subtle mottled/speckled texture rather than a smooth cartoon shell, consistent with the museum-specimen framing elsewhere in the UI (§6) — it should look like something just excavated, not manufactured.
- **Rarity signaling reuses the existing rarity-frame language from §3.2 exactly, applied to the shell instead of a card border:**

| Rarity | Shell treatment |
|---|---|
| Common | Plain grey-brown speckled shell, no glow |
| Rare | Bronze-flecked shell, faint glow |
| Epic | Silver-teal shell with fine crack-veins, particle sparkle |
| Legendary | Gold/amber shell, animated glow pulsing through the crack lines, ember particles |

- **The nest itself** should pick up the biome palette of whichever Dig Site it's from (§5) — an Arctic Dig egg sits in frost-dusted straw, a Volcanic Dig egg sits on cracked obsidian — so the pull screen quietly reinforces which biome pool the player is pulling from, the same way the Era palette (§3.1) reinforces unit identity elsewhere.
- **The "Amber-Sealed Specimen" guaranteed-Legendary ticket** (`MONETIZATION.md` §3) gets its own distinct visual: the egg encased in a chunk of amber rather than sitting in a nest — a direct, literal payoff of the currency name, and it should read as visibly more premium/different from a normal pull at a glance, not just a re-skinned egg.
- **Hatch beat:** the reveal animation is the egg physically cracking and splitting open (crack lines spreading across the shell, then the shell splitting into 2-3 pieces as the unit's chibi silhouette hops out) — see §7 for how this is deliberately kept visually distinct from the evolution-transformation glow-burst, so pulling a unit and evolving one stay two different kinds of payoff moment rather than reusing the same effect.

---

## 7. Animation Guidelines

- **Idle/walk cycles:** bouncy, 2-4 frame simplicity per state is enough (matches genre convention and keeps a 100+ unit roster producible) — do not over-invest in 12-frame realistic gait cycles.
- **Attack animation "anticipation":** every unit needs a clear, readable wind-up frame before its hit connects, since players track lane state at a glance during chaotic multi-unit fights — this is a functional requirement (telegraphing), not just polish.
- **Knockback reaction:** a unit knocked back should have a distinct squash + slide animation, since knockback is a core mechanic tied to the BU/lane-jam system (§4 of design doc) and needs to be immediately readable.
- **Evolution transformation:** a brief "fossil-glow cocoon → burst" transition when a unit evolves, reinforcing the fossil/excavation fiction at the moment of biggest player payoff.
- **Egg hatch (gacha pull):** a physical crack-and-split, not a glow-burst — see §6.1. Keeping this distinct from the evolution transformation above matters: two of the game's biggest reward moments (pulling a new unit, evolving one you own) should feel like different kinds of payoff, not the same effect recolored.

---

## 8. Logo & Branding

- **Wordmark concept:** "RoarFare" set in the chunky rounded display face, with the "O" in "Roar" styled as a cracked/fossilized circular shape (ties to the dig/fossil fiction) and a small claw-mark or crack accent under the wordmark rather than literal dinosaur clipart — keeps the logo scalable and legible at app-icon size.
- **App icon concept:** a single, instantly-readable silhouette (a chibi T. Rex head, three-quarter view, big eye, mouth slightly open) on the amber-gold background color from §3.4 — avoid a busy multi-character icon, which won't read at iOS home-screen size.
- **Color lock for branding:** amber-gold (`#E8A93B`) + dark umber (`#3B2A20`) as the two colors that must appear in every branding touchpoint (icon, splash screen, store listing), regardless of which Era palette a given piece of marketing art otherwise leans on.

---

## 9. Reference Direction (mood board notes, described)

Since this is a text spec rather than an image board, here's the intended reference triangulation for anyone (or any generation tool) producing actual art from this bible:

- **Shape/cute language:** Battle Cats' own unit sprites, Pokémon's chibi spinoffs (Pokémon Café ReMix-style proportions), classic toy-line dinosaur figures (chunky, rounded, saturated plastic-toy coloring).
- **Palette-by-biome discipline:** think themed amusement-park zones (each biome/land has one unmistakable palette) rather than a naturalistic muted-earth-tones documentary look.
- **UI/fossil framing:** natural history museum placards and specimen-drawer aesthetics — cream card stock, stamped seals, small serif "catalog number" details — as the connective tissue between menus and the paleontology fantasy.

If/when actual concept art is produced (e.g., via an image-generation tool), each prompt should explicitly carry: Era palette, size-class silhouette target, and "chibi toy-like, big eyes, rounded limbs" — dropping any of those three is the most likely way a generated asset drifts off-model.
