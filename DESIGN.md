# Cluster Conquerors of SPLORR!! — Design

Started November 10, 2026. This file is the specification. Sections: what is **Decided** (the user's calls, dated), the two trope inventories this design draws on, **Proposed** (Claude's mash-up suggestions, waiting on the user) and **Open** questions. Only the user moves an item to Decided. Stay in design until the user says to build.

## Decided

- **Name: Cluster Conquerors of SPLORR!!** (November 10, 2026). The user's choice, after a list of Orion-flavoured names.
- **An homage to Master of Orion, the original DOS version** (November 10, 2026, the user's words: "an homage to Masters of Orion, the original DOS version"). Inspired by its genre and systems; its races, names, story, text and art are not used (see `CLAUDE.md`).
- **Method: the Blustery Bulwark approach** (November 10, 2026): list the tropes of the original, list the tropes of SPLORR!! games, and mash them up.

## Master of Orion (1993): the tropes

Gathered November 10, 2026 from Claude's knowledge of the game (SimTex, designed by Steve Barcia, published by MicroProse, DOS, 1993); not checked against an outside source yet. Master of Orion II (1996) is a different game and is left out on purpose (no Antareans, no leaders, no buildings).

**Shape of the game**
- Turn-based 4X ("eXplore, eXpand, eXploit, eXterminate"; the term was coined in a review of this game). One star map seen from above, stars as coloured dots, everything else on menus.
- Galaxy sizes (small to huge), two to six empires (yer one and up to five computer rivals), five difficulty levels.
- **Two ways to win**: wipe out everyone, or be **elected by the Galactic Council**, which meets every so often once empires know each other and needs two thirds of the votes (votes follow population). Yer free to refuse the result and fight on.
- **Orion**: one legendary system holding a great planet and lost technology, guarded by a single unbeatable-looking monster (the Guardian). Taking it is a mid-game milestone.
- Random events: space monsters that wander and eat colonies, plagues, supernovas, derelict ships with free tech, rebellions, rich finds.

**Empire**
- Ten playable races, each one sentence long and one big trait (best researchers, best spies, best factories, best breeders, can live on any rock but grow slowly, better ship attack, better ship defence, better ground troops, better at diplomacy and trade).
- Each **colony has five sliders**: ships, defence, industry, ecology, technology. Ecology must clean up the pollution industry makes, or the planet shrinks. Moving one slider moves the others; the whole economy is these bars.
- Money is BC (billion credits) in a reserve; colonies grow population, then factories, capped by planet size and tech.
- Planet types run from Gaia and Terran down through Ocean, Arid, Desert, Tundra, Steppe, Jungle to the hostile ones (Barren, Dead, Inferno, Toxic, Radiated) that need tech to settle; rich, poor, ancient-artifact and hostile modifiers.
- **Range**: ships can only fly so far from yer colonies (fuel cells); range tech opens the map.

**Technology**
- Six fields (Computers, Construction, Force Fields, Planetology, Propulsion, Weapons), research spread across them by sliders.
- **Each game offers only a random subset** of each field's techs, so no empire can research everything; trade, steal or conquer for the rest.

**Ships and war**
- A design screen: four hull sizes, at most six designs in service at once, slots filled by weapons, shields, armour, computer, ECM, engines and specials. Old designs must be scrapped to make room.
- Fleets fly between stars over several turns. Colony ships, scouts, transports.
- Tactical combat on a small grid: stacks of identical ships with a count, missiles, beams, planetary missile bases.
- Invasion by **troop transports carrying population**; ground combat decides the planet.
- Nebulae slow ships and stop shields.

**Diplomacy and spying**
- Computer leaders with personalities and memories: treaties, trade agreements, alliances, tribute, threats, grudges.
- Spies placed per rival: steal tech, sabotage, and **frame a third empire** for it.

## SPLORR!! games: the tropes

Gathered November 10, 2026 from the vault (`Concepts/Metaphor design.md`, `Concepts/Starvation.md`, the Blustery Bulwark list, and the notes closest to this game: FREEDOM Haters (space, factions), Chaotic Space Mappers (space survey), Skirmishers (wargame), Gods (simulation), Investors (economy satire)).

**Identity**
- A **Metaphor**, not a game: the mechanic is the message. Mundane or absurd things played straight, deadpan short text, absurdist taglines, honest copy that never winks.
- The **"yer" voice** in every player-facing line.
- Double entendre played straight (Beaver Hunters, T!ts UUp!!, Handies for Cash!).
- Minimal retro presentation: 1-bit tiles (Urizen, Bountiful Bits, Bit Bonanza), DINOBYTE or small pixel fonts, text grids, Anvil-made sprites and sounds.

**Rules that recur**
- **Hated on purpose**: SIGMO in FREEDOM Haters is hostile to every faction, and a test keeps it so. The unfairness is the point.
- **Satire of institutions**: SIGMO's mandatory FREEDOM, levies and loans; Investors' shopkeeper who never says "price"; Bulwark's herald who claims every deed; Krimmis Inc.
- **Things that look like what they are not**: Chaotic Space Mappers' wormholes look exactly like unsurveyed stars; Bulwark's bosses are the cheapest thing that technically fits the boast.
- **Dice that only count on a six** (Key Seeker, Wonting, T!ts UUp!!); HeroQuest coloured dice (Skirmishers).
- **Gear wears out and breaks** (Key Seeker, Wonting, HamQuest, Bulwark).
- **Starvation**: a draining resource as the clock, refilled only at a place in the world (fuel in Chaotic Space Mappers, food in Bus Anticipator, battery in Robokitteh).
- **Locks and keys** gate areas, each key found in the area before.
- **Jools** as currency (and Crowns, with an exchange, in Wonting); monster **trophies** sold for coin.
- **Brutal on purpose**: weak start, lethal threats, "losing is fun".
- **A simulation that lives without you** (Gods: the tribe forages and dies on its own; you only nudge).
- **Survey before you know** (Chaotic Space Mappers: surveying reveals fuel, or a wormhole).

**How they are built and released**
- Odin to wasm, pure rules package with native tests, keyboard plus mouse plus gamepad plus touch, localStorage saves (often seed plus changes), simulators for balance (Skirmishers' `sim.sh`, Gods' 16-world runs).
- GitHub Pages first, then itch.io at one release a day; footer back links, AI disclosure, feedback form.

## Proposed (the user's to answer)

Each is a mash-up of a trope from each list. Options are lettered; pick one, several, or none.

1. **What is the Metaphor?** The heart of it, as "blustery" was for Bulwark.
   - A. *Conquest as paperwork*: every empire, yours included, runs on forms, levies and committees; the five sliders are a budget nobody can balance (FREEDOM Haters' bureaucracy, Investors' doublespeak).
   - B. *A clusterf\*\*\*, played straight*: "cluster" is the double meaning; everything goes wrong at once and the empires are all in the same mess, and nobody ever says the word.
   - C. *The council is a homeowners' association*: the Galactic Council meets about yer lawn (yer pollution, yer fleet parked in the wrong place), and winning the vote means becoming its president, which is a punishment.
   - D. *Everybody hates you* (the SIGMO rule): the rivals start hostile and stay that way; the Metaphor is being the one nobody wants on the council.
2. **Scale.** A. Small and quick: one cluster of about 12 to 20 stars, two to four empires, an evening a game. B. MoO-sized: up to huge galaxies, six empires, many evenings. C. Fixed: one hand-tuned cluster size.
3. **The sliders.** A. Keep the five per colony, renamed in the Metaphor's words. B. One set of sliders for the whole empire (simpler on a phone). C. Fewer sliders (say three) per colony.
4. **Orion's stand-in.** The legendary system and its guardian, twisted as Bulwark twisted its bosses. A. The legend is true and the guardian is real and hard. B. The cheapest thing that technically fits the legend (a sign reading "Guardian", a very large space moth). C. Everyone has heard of it; nobody can find it (it looks like an ordinary star, like a wormhole in Chaotic Space Mappers, until surveyed).
5. **Surveying.** Stars start unknown; a scout surveys them to show planet type and specials, and some are not what they look like (wormholes, dead rocks reported as Gaia by a bad sensor). A. Yes. B. MoO's way: types visible in range, details on arrival.
6. **Combat.** A. MoO-style tactical grid with ship stacks, rolls hidden. B. Tactical grid with SPLORR!! dice that only count on a six. C. Skirmishers' HeroQuest dice on the grid. D. Auto-resolved, with a battle report.
7. **Ship design.** A. MoO's design screen: hull sizes, slots, at most six designs. B. A short fixed list of ship types that tech upgrades. C. MoO's screen, and ships wear out (the SPLORR!! gear rule) and need refitting at a shipyard.
8. **Range and starvation.** A. Fuel as the clock: ships burn fuel away from colonies and are stranded at zero (Chaotic Space Mappers). B. MoO's hard range limit only. C. Both.
9. **The races.** A. Original races, each one sentence and one trait, in the deadpan voice (none of MoO's ten). B. No races: every empire is the same kind of people, told apart only by the leader's personality. C. You play one fixed empire (a SIGMO-like satire); rivals have races.
10. **Technology.** A. Six fields and a random subset per game, as in MoO, renamed. B. A short fixed tree. C. Random subset, and tech can only be had by trade, theft or conquest for the fields yer bad at.
11. **Diplomacy and spies.** A. MoO's full set (treaties, trade, tribute, spies who can frame a rival). B. A few verbs only (trade, threaten, tribute). C. No diplomacy beyond the council vote.
12. **Money.** A. Jools. B. Jools and a second coin with an exchange (Wonting). C. MoO's BC, renamed.

Also needed later, as for Bulwark: art (Urizen or another CC0 set, or a text grid like FREEDOM Haters), font (DINOBYTE?), the interface on each input, landscape or portrait, and a story or ending if the Metaphor wants one.

## Open

- All twelve proposals above, and the presentation questions under them.
