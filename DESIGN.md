# Cluster Conquerors of SPLORR!! — Design

Started November 10, 2026. This file is the specification. Sections: what is **Decided** (the user's calls, dated), the two trope inventories this design draws on, **Proposed** (Claude's mash-up suggestions; all answered November 10, 2026) and **Open** questions. Only the user moves an item to Decided. Stay in design until the user says to build.

## Decided

- **Name: Cluster Conquerors of SPLORR!!** (November 10, 2026). The user's choice, after a list of Orion-flavoured names.
- **An homage to Master of Orion, the original DOS version** (November 10, 2026, the user's words: "an homage to Masters of Orion, the original DOS version"). Inspired by its genre and systems; its races, names, story, text and art are not used (see `CLAUDE.md`).
- **Method: the Blustery Bulwark approach** (November 10, 2026): list the tropes of the original, list the tropes of SPLORR!! games, and mash them up.

The twelve proposals and four presentation questions were answered one at a time on November 10, 2026:

- **The Metaphor: all four at once** (proposal 1, options A, B, C and D). *Conquest as paperwork*: every empire, yers included, runs on forms, levies and committees, and the sliders are a budget nobody can balance. *A clusterf\*\*\*, played straight*: everything goes wrong at once, every empire is in the same mess, and nobody ever says the word. *The Galactic Council is a homeowners' association*: it meets about yer lawn (pollution, a fleet parked in the wrong place), and winning the vote makes you its president, which is a punishment. *Everybody hates you* (the SIGMO rule): rivals start hostile and stay that way; yer the one nobody wants on the council.
- **Scale: MoO-sized** (proposal 2, B): galaxy sizes up to huge, up to six empires, many evenings a game.
- **Sliders: five per colony** (proposal 3, A): MoO's ships, defence, industry, ecology and technology, renamed in the Metaphor's words.
- **The legendary system: the cheapest fit** (proposal 4, B): the Orion stand-in's guardian is the cheapest thing that technically fits the legend (a sign reading "Guardian", a very large space moth), still dangerous, as Bulwark's bosses are.
- **Surveying first** (proposal 5, A): stars start unknown; a scout surveys them to show planet type and specials, and some are not what they look like (wormholes, a dead rock reported as Gaia by a bad sensor).
- **Combat: MoO's tactical grid, rolls hidden** (proposal 6, A): stacks of identical ships on a grid; to-hit and damage worked out behind the scenes.
- **Ships: fixed types** (proposal 7, B): a short fixed list of ship types that technology upgrades; no design screen.
- **Range: fuel is the clock** (proposal 8, A): ships burn fuel away from yer colonies and are stranded at zero, as in Chaotic Space Mappers; refuel at colonies or surveyed stars.
- **Races: original ones** (proposal 9, A): none of MoO's ten; each one sentence and one big trait, in the deadpan voice; the player picks one.
- **Technology: MoO's six fields and a random subset** (proposal 10, A): six fields, renamed, funded by the technology slider; each game offers a random subset of each field's techs, so nobody gets everything.
- **Diplomacy: MoO's full set** (proposal 11, A): treaties, trade, tribute, threats, and spies who steal, sabotage and frame a rival, all with empires that hate you anyway.
- **Money: BJ, "billion jools"** (proposal 12, the user's own answer): MoO's BC becomes BJ.
- **Art: the Urizen 1-bit tileset** (vurmux, CC0, 12 by 12). **Font: DINOBYTE** (mby, CC BY 4.0, 6 by 8; credit required).
- **Interface: equal for all inputs, landscape only** (as Bulwark): every screen for mouse, keyboard, gamepad and touch from the start; phones play turned sideways.
- **Story: light framing only**: no story arc; an opening line, race blurbs, council minutes and news items carry the Metaphor.

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

## Proposed

The twelve proposals put to the user on November 10, 2026 are all answered; see Decided. (Options not chosen: a small or fixed cluster; empire-wide or fewer sliders; a true-and-hard or unfindable legend; MoO's visible planet types; sixes-only or HeroQuest dice or auto-resolved battles; MoO's design screen, with or without wear; MoO's hard range limit; no races or one fixed empire; a fixed tree or closed weak fields; fewer diplomatic verbs or the vote only; plain Jools, two coins, or BC renamed.)

## Open

- **Stack** (not asked; the vault default is Odin to `js_wasm32` with a canvas software framebuffer, as in Bulwark).
- **Details to settle later:** the races and their traits; the slider, field and ship-type names in the Metaphor's words; the ship-type list; fuel numbers; the legend's guardian; council timing and HOA business; what the surveys can lie about; the computer rivals' behaviour; venue and Pages timing.
