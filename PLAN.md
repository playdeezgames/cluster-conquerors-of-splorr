# Cluster Conquerors of SPLORR!! — Plan

Drafted November 10, 2026. `DESIGN.md` is the specification; this file is how it gets built, one playable slice at a time. Everything under "Proposed" is Claude's suggestion until the user decides it; numbers are starting values to tune by playing. Nothing is built until the user says to build.

## Slices

1. **The neighbourhood** (this plan): the smallest galaxy, you and two rivals, the whole explore, expand, exploit loop, tactical combat and invasion, the Clubhouse and its moth, and the HOA council's complaints and vote. A game you can win, lose and be elected in.
2. **Proposed: the paperwork.** Diplomacy (treaties, trade, tribute, threats), spies (steal, sabotage, frame), bylaws, the presidency's duties in full, all ten races offered, random events.
3. **Proposed: the subdivision.** All galaxy sizes up to huge, up to six empires, the computer rivals' personalities, balance with a simulator (as Skirmishers' `sim.sh`), sound, the cover, then itch.io on a Coxswain-booked day.

## Slice 1: the neighbourhood

**Goal:** a complete game in an evening: pick a race, survey a cluster of about 20 stars that sometimes lies to you, settle it with Moving Vans, run each colony on the five HOA-chore sliders, research the six hobbies, keep ships fuelled, fight two rivals who hate you and each other, try the Clubhouse's moth, and sit through council meetings that fine you until one elects somebody. Conquest ends the game; being elected president is a win and play goes on (duties are minimal in this slice).

**In the slice**
- One galaxy size, "small": about 20 stars on a map larger than the screen, scrolling, generated from a per-game seed with splitmix64 (the same on wasm and native).
- Three empires: the player and two computer rivals, races drawn from a slice-1 subset (proposed below).
- Surveying with Inspectors, and all four survey lies.
- Colonies with population, factories, pollution, the five sliders, and BJ.
- The six tech fields with a random subset per game; automatic upgrades with a per-ship fee.
- All seven ship types, building, fleets moving between stars over turns, fuel and stranding, Gas Cans.
- Tactical combat on a small grid with stacks and hidden rolls; Carpools invading with ground combat.
- The Clubhouse, its porch light and the very large space moth.
- The HOA council: complaints with fines, and the presidential vote (votes follow population, two thirds to win).
- Saves in localStorage (seed plus changes where it fits, whole state otherwise).
- All four inputs on every screen; landscape; the release layout and footer from the first commit.

**Not in the slice:** diplomacy and spies, bylaws, the presidency's full duties, larger galaxies, more than three empires, random events, sound beyond a few effects, the cover and title art (placeholder only), LootLocker.

## Proposed for slice 1

**Screen:** a 480 by 270 framebuffer (16:9; 80 by 33 DINOBYTE cells, 40 by 22 Urizen tiles), Sweetie-16 or another 16-colour palette. The star map fills the left, a side panel on the right shows the selected star, colony or fleet, and a one-line news ticker runs along the bottom. Bigger than Bulwark's 384 by 216 because a 4X is mostly text.

**Tiles (Urizen, from the catalogues; check each by eye before use):** stars from (78–83, 21); planets from (78–87, 19) for the colony and survey screens; moons and asteroids (78–82, 20) for dead rocks; vehicles (52–76, 7) for the ships (a van for the Moving Van, a bus for the Carpool, a car for the Golf Cart, a pickup or tractor, the tank for the Monster Truck; the Gas Can and Inspector from items or the bicycle and scooter); the 2 by 2 pale winged moth from the large monsters (26–45, 48–49) for the guardian; the slice's race animals from (0–15, 15–16) where the sheet has them, otherwise a coloured flag per empire.

**Races in slice 1 (proposed):** the player picks from four: **Beavers** (industry), **Owls** (research), **Rabbits** (growth), **Geese** (ship attack). Rivals are drawn from the same four. The other six arrive in slice 2. Each trait as a plain modifier: Beavers +50 % factory output, Owls +50 % research, Rabbits +50 % growth, Geese +20 % to hit in combat.

**Stars and planets:** each star has one planet (as in Master of Orion) of a type from Garden down to Dead, a size (Small, Medium, Large), and maybe a special (Rich, Poor, Ancient Artifacts). Hostile types need a Landscaping tech to settle. One random star is the Clubhouse (a Garden world with Artifacts and lost tech: three techs from any field once taken); one in eight stars is a wormhole that looks like an unsurveyed star.

**Survey lies (starting rates):** an Inspector's report has a 15 % chance to misstate the type or size (put right when a Moving Van arrives); a reported special is false 25 % of the time (found out when a colony has lived there a few turns); each turn, each filed report has a 1 % chance to be lost (the star shows unknown again, "misfiled"). A wormhole throws whatever enters it to a random star; surveying it from the next system names it.

**Colonies and sliders:** population grows towards the planet's maximum (Parking, Fencing, Home Improvement, Lawn Care, Book Club share the colony's production; moving one moves the others, as in Master of Orion). Home Improvement builds factories (each worked by one population unit); factories make pollution that Lawn Care must clean, or the planet's maximum population shrinks; Fencing builds defence bases; Parking builds the colony's ship order; Book Club makes research points. Production goes to BJ only through taxes in slice 1 (a flat rate, 10 %). The panel shows each slider as a bar with a lock, as in Master of Orion.

**Technology:** six fields (Spreadsheets, Renovation, Fences, Landscaping, Commuting, Disputes), each with about eight techs in slice 1 of which a random five are offered per game. Research is spread over the fields by a second set of sliders, empire-wide. Commuting raises speed and fuel capacity; Disputes gives weapons; Fences shields; Renovation armour and cheaper factories; Spreadsheets to-hit and survey accuracy (fewer bad readings); Landscaping lets you settle hostile types and raises population. Upgrade fee: 5 BJ per ship per upgrade, billed when the tech arrives; unpaid ships are marked "Unpaid" and keep the old tech until paid from the fleet screen.

**Ships (starting values):**
| Type | Role | Cost (BJ of production) | Fuel (turns away) | Notes |
| --- | --- | --- | --- | --- |
| Inspector | scout, surveys | 10 | 6 | unarmed |
| Moving Van | colony ship | 60 | 4 | used up founding a colony |
| Carpool | troop transport | 20 | 4 | carries population to invade |
| Gas Can | tanker | 25 | 8 | refuels ships in its system, holds 10 refills |
| Golf Cart | small warship | 20 | 4 | 1 weapon |
| Pickup | medium warship | 50 | 4 | 2 weapons, some armour |
| Monster Truck | large warship | 120 | 3 | 4 weapons, heavy armour |

Fuel counts turns spent away from a refuelling place (own colonies, a Gas Can in the system, a treaty partner's colony once diplomacy exists); a ship at zero is stranded and waits until a Gas Can reaches it or a colony is founded at its star.

**Combat:** when hostile fleets or a fleet and a colony meet, a 10 by 8 tactical grid opens; each side's ships are stacks of one type with a count; each turn every stack moves and fires (Golf Carts fast, Monster Trucks slow); colonies fire from their defence bases. Rolls are hidden: the log says hits, losses and retreats. A side may retreat to a star it came from. The player can also let the battle auto-resolve (proposed; Master of Orion had no such button, but it helps the computer-against-computer battles and speeds things up). Computer-against-computer battles resolve without a screen and appear in the news.

**Invasion:** Carpools arriving at an undefended (no bases left) enemy colony land their population; ground combat with hidden rolls against the colony's population; the winner keeps the planet.

**The Clubhouse moth:** it sits at the Clubhouse and never leaves; strength of about three Monster Trucks; anything that enters the system fights it. Its line on inspect: "Drawn by the porch light."

**The HOA council (proposed timing):** first meets once every empire has met the others, then every 25 turns. Each meeting: one or two complaints against empires (pollution over a threshold, a fleet parked at another empire's star, an unpaid upgrade fee), each fined 5 % of the empire's BJ; the vote every second meeting. Votes follow population; a candidate needs two thirds. The computer rivals never vote for you (everybody hates you) and rarely for each other. If you win: "President of the Homeowners' Association" is recorded as a win, play goes on, and in slice 1 the duty is attending: each later meeting costs the president 10 BJ.

**Computer rivals (slice 1):** simple and honest: expand to the nearest good unsurveyed or surveyed star, balance sliders by rule of thumb, build warships when a hostile fleet is near, attack the weakest neighbour (the player or the other rival) when stronger. No cheating, same fog of war.

**Text (to draft for review in the steps):** the opening line, one sentence per race, the complaint wording ("Complaint received regarding: a Pickup parked at Lot 7."), news items, the moth's lines, the presidential notice.

## Build order (each step ends playable in the browser and tested natively)

0. **Scaffold:** `src/` rules package (`package game`, no `core:os` or `core:fmt`) and web layer, `tools/test.sh`, `build.sh`, `serve.sh`, `pages.sh`, `ship.sh` plus `shippit.sh`, `web/index.html` with the footer (credits, AI disclosure, back links, "Send feedback"), Urizen and DINOBYTE packed by a `tools/extract_gfx.py` with licence records, a placeholder `assets/cover.png`, an `ITCH_DESCRIPTION.md` draft, a launch config for the browser pane. A framebuffer on a canvas, crisp scaling, the map, panel and ticker laid out; a cursor that moves on all four inputs.
1. **A cluster to look at:** the galaxy generator (about 20 stars, a minimum spacing, names from a list), a scrolling star map, a cursor and selection on all four inputs (keys and d-pad move between stars, mouse and touch pick them), the home colony, unknown stars drawn alike (wormholes among them). **Then GitHub Pages**, at the user's go-ahead (decided: Pages as soon as a galaxy map can be explored).
2. **Fleets, fuel and surveying:** turns (an End Turn on every input), ships at stars, sending a fleet (distance in turns), Inspectors surveying, the four lies, fuel counting, stranding, Gas Cans refuelling, wormholes moving ships.
3. **Colonies and sliders:** the colony screen with the five sliders and locks, population, factories, pollution, defence bases, building ships, BJ from taxes, Moving Vans founding colonies on surveyed planets (bad readings put right on arrival).
4. **Technology:** the six fields and their research sliders, the random subset, techs taking effect, the per-ship upgrade fee and Unpaid ships.
5. **The rivals:** race choice at the start (slice-1 four), two computer empires with fog of war, expanding and building by the rules above, contact between empires, everyone hostile.
6. **Combat:** the tactical grid, stacks, movement, hidden rolls, retreat, auto-resolve, battles against colonies, computer-against-computer battles in the news.
7. **Invasion and conquest:** Carpools, ground combat, captured colonies, an empire's elimination, the conquest win and the loss screen.
8. **The Clubhouse and the council:** the moth, the Clubhouse's lost tech, council meetings with complaints and fines, the vote, the presidency's slice-1 duty.
9. **Saves and polish:** saves, a first balance pass (a native simulator playing computer against computer, as in Skirmishers), screenshots and the portal picture, the slice-1 notice of what is still coming, then Pages updated when the user says so.

## Decided for slice 1 (November 10, 2026, one at a time)

- **Screen: 480 by 270** (80 by 33 DINOBYTE cells, 40 by 22 Urizen tiles).
- **Races: the proposed four**: Beavers (+50 % factory output), Owls (+50 % research), Rabbits (+50 % growth), Geese (+20 % to hit). The other six arrive in slice 2.
- **Star names: both**: stars carry straight names ("Vega Minor"); the HOA's paperwork (complaints, fines, news) refers to them by lot numbers ("Lot 7").
- **Auto-resolve: yes**: the player may fight a battle on the grid or let it resolve with the same hidden rolls and read the report.
- **Captured colonies keep their race and file complaints**: the people keep their race and its trait on that colony, and lodge a complaint against their new owner at every council meeting until assimilated over time (how long: a number for step 7).
- **Numbers: start with the proposed ones, tune later**: build with the values above; each is reviewed in the step that adds it and in the step 9 balance pass, as with Bulwark.

## Open for slice 1

- Every number, for review step by step. Assimilation time for captured colonies (step 7).
- The text drafts (opening line, race sentences, complaint wording, news, the moth's lines, the presidential notice), for review as each step lands.
