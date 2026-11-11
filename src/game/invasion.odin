package game

// Invasion and conquest (slice 1 step 7). Carpools carry households; at an enemy colony with no bases
// and no ships left to stop them, they land at the start of the next turn and fight the colony's
// militia (half its households), one against one, with hidden even odds. Win, and the colony is yers,
// its people still their own species (and with their own trait) until they assimilate. An empire with
// no colonies left is out; the last one standing has conquered the cluster.

CARPOOL_LOAD :: 5 // households a Carpool takes from the colony that builds it, and lands
ASSIMILATE_TURNS :: 20 // turns before a captured colony's people become the owner's species
LAND_WIN_PERCENT :: 50 // a landed household's chance against one of the militia

Outcome :: enum u8 {
	Playing,
	Won,
	Lost,
}

// Carpools land wherever nothing is left to stop them.
land_troops :: proc(g: ^Game) {
	for i in 0 ..< g.star_count {
		c := any_colony(g, i)
		if c == nil || c.bases > 0 || fleet_of(g, i, c.owner) != nil {
			continue
		}
		for e in 0 ..< g.empire_count {
			if e == c.owner {
				continue
			}
			f := fleet_of(g, i, e)
			if f == nil || f.ships[.Carpool] == 0 {
				continue
			}
			invade(g, i, f)
			c = any_colony(g, i)
			if c == nil || c.owner == e {
				break
			}
		}
	}
}

// One landing: every Carpool at the star unloads, and the fight goes until one side is spent.
invade :: proc(g: ^Game, star: int, f: ^Fleet) {
	c := any_colony(g, star)
	defender := c.owner
	attacker := f.owner
	troops := f.ships[.Carpool] * CARPOOL_LOAD
	f.ships[.Carpool] = 0
	if fleet_size(f) == 0 {
		f^ = {}
	}
	militia := (c.households + 1) / 2
	fallen := 0
	for troops > 0 && militia > 0 {
		if rng_int(&g.rng, 100) < LAND_WIN_PERCENT {
			militia -= 1
			fallen += 1
		} else {
			troops -= 1
		}
	}
	c.households = max(0, c.households - fallen)
	s := &g.stars[star]
	won := militia == 0 && troops > 0
	if won {
		race := c.race
		c^ = {
			owned      = true,
			owner      = attacker,
			race       = race,
			households = max(1, c.households),
			factories  = c.factories,
			wear       = c.wear,
			waste      = c.waste,
			age        = SPECIAL_FOUND_OUT,
			slider     = NEW_SLIDERS,
			build      = .Inspector,
		}
		if race != g.empires[attacker].race {
			c.captured = 1
		}
		s.reports[attacker] = {
			filed   = true,
			planet  = s.planet,
			size    = s.size,
			special = s.special,
		}
	}
	if attacker != PLAYER && defender != PLAYER && !g.empires[PLAYER].sees[star] {
		return
	}
	b: Text
	add(&b, s.name)
	add(&b, " (Lot ")
	add_int(&b, star + 1)
	add(&b, "): ")
	switch {
	case won && attacker == PLAYER:
		add(&b, "yer Carpools take it. ")
		add_int(&b, c.households)
		add(&b, " ")
		add(&b, RACES[c.race].name)
		add(&b, " households now pay yer HOA dues.")
	case won && defender == PLAYER:
		add(&b, "the ")
		add(&b, empire_name(g, attacker))
		add(&b, " landed and took it.")
	case won:
		add(&b, "the ")
		add(&b, empire_name(g, attacker))
		add(&b, " took it from the ")
		add(&b, empire_name(g, defender))
		add(&b, ".")
	case attacker == PLAYER:
		add(&b, "yer Carpools landed and were seen off.")
	case:
		add(&b, "the ")
		add(&b, empire_name(g, attacker))
		add(&b, " landed and were seen off.")
	}
	say(g, text(&b))
}

// Captured people come round, slowly.
assimilate :: proc(g: ^Game) {
	for i in 0 ..< g.star_count {
		c := any_colony(g, i)
		if c == nil || c.captured == 0 {
			continue
		}
		c.captured += 1
		if c.captured > ASSIMILATE_TURNS {
			c.race = g.empires[c.owner].race
			c.captured = 0
			b: Text
			add(&b, "The households of ")
			add(&b, g.stars[i].name)
			add(&b, " (Lot ")
			add_int(&b, i + 1)
			add(&b, ") now consider themselves ")
			add(&b, RACES[c.race].name)
			add(&b, ".")
			tell(g, c.owner, text(&b))
		}
	}
}

colonies_of :: proc(g: ^Game, owner: int) -> int {
	n := 0
	for i in 0 ..< g.star_count {
		if colony_of(g, i, owner) != nil {
			n += 1
		}
	}
	return n
}

// Empires with no colonies are out (their ships go home to nobody); the game ends when you are out or
// the last one left.
check_conquest :: proc(g: ^Game) {
	for e in 0 ..< g.empire_count {
		emp := &g.empires[e]
		if emp.out || colonies_of(g, e) > 0 {
			continue
		}
		emp.out = true
		for &f in g.fleets {
			if f.used && f.owner == e {
				f = {}
			}
		}
		if e != PLAYER && g.empires[PLAYER].met[e] {
			b: Text
			add(&b, "The ")
			add(&b, empire_name(g, e))
			add(&b, " have no colonies left. Their ships go home to nobody.")
			say(g, text(&b))
		}
	}
	if g.outcome != .Playing {
		return
	}
	if g.empires[PLAYER].out {
		g.outcome = .Lost
		g.mode = .Game_Over
		return
	}
	if g.empire_count < 2 {
		return // nobody to conquer (a test's hand-made cluster)
	}
	for e in 1 ..< g.empire_count {
		if !g.empires[e].out {
			return
		}
	}
	g.outcome = .Won
	g.mode = .Game_Over
}
