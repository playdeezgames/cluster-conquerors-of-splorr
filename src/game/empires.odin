package game

// Empires (slice 1 step 5): you and two computer rivals, each an animal species played straight, each
// with its own BJ, research, survey reports and sight. Everybody hates everybody.

PLAYER :: 0
MAX_EMPIRES :: 3
NO_OWNER :: -1
SIGHT_RANGE :: 7 // cells an empire can see from its colonies and ships

// The slice-1 four first, so their numbers in old saves still mean the same species.
Race :: enum u8 {
	Beavers, // industry
	Owls, // research
	Rabbits, // growth
	Geese, // ship attack
	Raccoons, // spies
	Ants, // more factories per household
	Tardigrades, // any rock, slow growth
	Tortoises, // ship defence
	Badgers, // ground troops
	Dogs, // treaties and trade
}

Race_Info :: struct {
	name:  string, // "Beavers"
	one:   string, // "Beaver"
	blurb: string,
	trait: string,
	later: string, // what the trait waits for, while it does nothing yet ("" once it works)
}

// All ten (DESIGN.md; the six after the Geese arrived in slice 2 step 0).
RACES := [Race]Race_Info {
	.Beavers     = {"Beavers", "Beaver", "Build whether or not anyone asked.", "Factories make half as much again.", ""},
	.Owls        = {"Owls", "Owl", "Read everything, finish nothing.", "Research comes half as fast again.", ""},
	.Rabbits     = {"Rabbits", "Rabbit", "You know.", "Households grow half as fast again.", ""},
	.Geese       = {"Geese", "Goose", "Honk, then attack.", "Ships aim a fifth better in battle.", ""},
	.Raccoons    = {"Raccoons", "Raccoon", "Masked, into everything.", "Watchers work half as well again, and get caught half as often.", ""},
	.Ants        = {"Ants", "Ant", "A hundred to a job.", "Each household works three factories, not two.", ""},
	.Tardigrades = {"Tardigrades", "Tardigrade", "Live on any rock. Grow slowly.", "Settle any world without Landscaping; grow at half speed.", ""},
	.Tortoises   = {"Tortoises", "Tortoise", "The shell is the plan.", "Enemy shots hit a fifth less often.", ""},
	.Badgers     = {"Badgers", "Badger", "Dig in.", "Win 65 of 100 fights on the ground, not 50.", ""},
	.Dogs        = {"Dogs", "Dog", "Like everybody. Everybody still hates them.", "Grudges start lower; trade pays half as much again.", ""},
}

// The colour each empire's colonies and ships are drawn in.
EMPIRE_COLORS := [MAX_EMPIRES]u8{COLOR_GREEN, COLOR_RED, COLOR_ORANGE}

Empire :: struct {
	race:     Race,
	home:     int,
	bj:       int, // billion jools
	research: int, // this turn's research points, shared out at the turn's end
	tech:     Research,
	met:      [MAX_EMPIRES]bool, // has seen this empire's colonies or ships
	sees:     [MAX_STARS]bool, // stars in sight this turn
	intel:    [MAX_STARS]Intel, // what it last saw at each star
	out:      bool, // no colonies left
	grudge:   [MAX_EMPIRES]int, // how much it hates each empire, 0 to 100 (grudges.odin); hidden
	mood:     Mood, // the gossip band of its grudge against you, last time you heard
	watch_share: int, // percent of BJ income to the Neighbourhood Watch (watch.odin)
	watch_saved: int, // BJ towards the next watcher
	watchers: int, // at home, looking out for the others'
	placed:   [MAX_EMPIRES]int, // watchers on each rival
	mission:  [MAX_EMPIRES]Mission,
}

// What an empire last saw at a star: whose colony, and how much there could fight back.
Intel :: struct {
	seen:     bool,
	owner:    int, // the colony's owner, or NO_OWNER
	strength: int, // hits of everything armed there that is not the watcher's (bases count)
	households: int, // the colony's, if there is one
}

// Hits of everything armed at a star that is not `except`'s: bases and armed ships.
strength_at :: proc(g: ^Game, star, except: int) -> int {
	n := 0
	if star == g.clubhouse && g.moth_alive {
		n += MOTH_COMBAT.hp
	}
	if c := any_colony(g, star); c != nil && c.owner != except {
		n += c.bases * BASE_COMBAT.hp
	}
	for &f in g.fleets {
		if f.used && f.star == star && f.owner != except {
			for c, t in f.ships {
				if COMBAT[t].weapons > 0 {
					n += c * COMBAT[t].hp
				}
			}
		}
	}
	return n
}

// Messages for the news ticker only matter when they are about you.
tell :: proc(g: ^Game, owner: int, s: string) {
	if owner == PLAYER {
		say(g, s)
	}
}

MOTH :: -2 // the Clubhouse's guardian, as a side in a battle

empire_name :: proc(g: ^Game, owner: int) -> string {
	if owner == MOTH {
		return "moth"
	}
	return RACES[g.empires[owner].race].name
}

owner_color :: proc(owner: int) -> u8 {
	return owner == MOTH ? COLOR_LIGHT : EMPIRE_COLORS[owner]
}

// Picks the rivals' species once you have chosen yers: two of the other nine, at random.
assign_rivals :: proc(g: ^Game) {
	mine := g.empires[PLAYER].race
	others: [len(Race) - 1]Race
	n := 0
	for r in Race {
		if r != mine {
			others[n] = r
			n += 1
		}
	}
	for i := n - 1; i > 0; i -= 1 {
		j := rng_int(&g.rng, i + 1)
		others[i], others[j] = others[j], others[i]
	}
	for e in 1 ..< g.empire_count {
		g.empires[e].race = others[e - 1]
	}
	reset_grudges(g)
}

// Where an empire's eyes are: its colonies and its ships, docked or on the way.
update_sight :: proc(g: ^Game) {
	for e in 0 ..< g.empire_count {
		g.empires[e].sees = {}
	}
	look :: proc(g: ^Game, owner, x, y: int) {
		for i in 0 ..< g.star_count {
			s := g.stars[i]
			dx, dy := s.x - x, s.y - y
			if dx * dx + dy * dy <= SIGHT_RANGE * SIGHT_RANGE {
				g.empires[owner].sees[i] = true
			}
		}
	}
	for i in 0 ..< g.star_count {
		if c := any_colony(g, i); c != nil {
			look(g, c.owner, g.stars[i].x, g.stars[i].y)
		}
	}
	for &f in g.fleets {
		if f.used {
			x, y := fleet_cell(g, &f)
			look(g, f.owner, x, y)
		}
	}
	watch_sight(g)
	// Allies share what they see.
	own: [MAX_EMPIRES][MAX_STARS]bool
	for e in 0 ..< g.empire_count {
		own[e] = g.empires[e].sees
	}
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if a != b && allied(g, a, b) {
				for i in 0 ..< g.star_count {
					g.empires[a].sees[i] ||= own[b][i]
				}
			}
		}
	}
	for o in 0 ..< g.empire_count {
		for i in 0 ..< g.star_count {
			if !g.empires[o].sees[i] {
				continue
			}
			owner := NO_OWNER
			if c := any_colony(g, i); c != nil {
				owner = c.owner
			}
			g.empires[o].intel[i] = {
				seen       = true,
				owner      = owner,
				strength   = strength_at(g, i, o),
				households = owner == NO_OWNER ? 0 : any_colony(g, i).households,
			}
		}
	}
	// First contact: an empire's colony or ships in another's sight.
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			if a == b || g.empires[a].met[b] {
				continue
			}
			spot := NO_STAR
			for i in 0 ..< g.star_count {
				if !g.empires[a].sees[i] {
					continue
				}
				if c := any_colony(g, i); c != nil && c.owner == b {
					spot = i
					break
				}
				if fleet_of(g, i, b) != nil {
					spot = i
					break
				}
			}
			if spot == NO_STAR {
				for &f in g.fleets {
					if f.used && f.owner == b && f.star == NO_STAR && sees_cell(g, a, &f) {
						spot = f.to
						break
					}
				}
			}
			if spot == NO_STAR {
				continue
			}
			g.empires[a].met[b] = true
			if a == PLAYER {
				t: Text
				add(&t, "First contact: the ")
				add(&t, empire_name(g, b))
				add(&t, ", near ")
				add(&t, g.stars[spot].name)
				add(&t, " (Lot ")
				add_int(&t, spot + 1)
				add(&t, "). They hate you. The Homeowners' Association has been notified.")
				say(g, text(&t))
			}
		}
	}
}

// Whether a fleet in transit is close enough to anything of the owner's to be seen.
sees_cell :: proc(g: ^Game, owner: int, f: ^Fleet) -> bool {
	x, y := fleet_cell(g, f)
	for i in 0 ..< g.star_count {
		s := g.stars[i]
		if !g.empires[owner].sees[i] {
			continue
		}
		mine := false
		if c := any_colony(g, i); c != nil && c.owner == owner {
			mine = true
		}
		if fleet_of(g, i, owner) != nil {
			mine = true
		}
		dx, dy := s.x - x, s.y - y
		if mine && dx * dx + dy * dy <= SIGHT_RANGE * SIGHT_RANGE {
			return true
		}
	}
	return false
}

// The map cell a fleet is at (part way along, if in transit).
fleet_cell :: proc(g: ^Game, f: ^Fleet) -> (x, y: int) {
	if f.star != NO_STAR {
		return g.stars[f.star].x, g.stars[f.star].y
	}
	a, b := g.stars[f.from], g.stars[f.to]
	done := f.total - f.left
	t := max(1, f.total)
	return a.x + (b.x - a.x) * done / t, a.y + (b.y - a.y) * done / t
}
