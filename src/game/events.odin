package game

// Random events (slice 2 step 8): the cluster's bad luck, and now and then some good. From turn 10, one
// turn in 15 something happens to an empire picked at random by households (bigger empires, more
// luck of both kinds), usually at one of its colonies:
//   a stray Goat turns up at a star and wanders, a star a turn, eating 2 households a turn wherever
//     there is a colony, until armed ships or bases there see it off (it has 20 hits);
//   a Flu going round takes a fifth of a colony's households over 5 turns;
//   a Star going out (one event in 50): a colony that is not a home is lost, and the planet is Dead;
//   an abandoned car with a tech in the glovebox, from any field;
//   a Residents' Revolt: a colony does nothing for 5 turns;
//   a Find in the Attic: 50 to 150 BJ, or the planet turns out Rich.
// Each is in the news if it is yers (or in sight), and on yer doormat if it is yers.

EVENT_IN :: 15 // one turn in this many
EVENTS_FROM :: 10 // the first turn an event can happen
STAR_OUT_IN :: 50 // one event in this many is a star going out
GOAT_HITS :: 20
GOAT_EATS :: 2 // households a turn
FLU_TURNS :: 5
REVOLT_TURNS :: 5
FIND_MIN :: 50
FIND_MAX :: 150

Event :: enum u8 {
	Goat,
	Flu,
	Star_Out,
	Car,
	Revolt,
	Find,
}

Goat :: struct {
	alive: bool,
	star:  int,
	hp:    int,
}

// Each turn: the Goat's turn, then perhaps an event.
events_turn :: proc(g: ^Game) {
	goat_turn(g)
	if g.turn < EVENTS_FROM || rng_int(&g.rng, EVENT_IN) != 0 {
		return
	}
	e := pick_unlucky(g)
	if e == NO_OWNER {
		return
	}
	ev := Event(1 + rng_int(&g.rng, len(Event) - 1)) // not the Goat or the star yet
	if ev == .Star_Out {
		ev = .Goat
	}
	if rng_int(&g.rng, STAR_OUT_IN) == 0 {
		ev = .Star_Out
	}
	happen(g, ev, e)
}

// An empire, picked at random by households.
pick_unlucky :: proc(g: ^Game) -> int {
	total := 0
	for e in 0 ..< g.empire_count {
		if !g.empires[e].out {
			total += households_of(g, e)
		}
	}
	if total <= 0 {
		return NO_OWNER
	}
	r := rng_int(&g.rng, total)
	for e in 0 ..< g.empire_count {
		if g.empires[e].out {
			continue
		}
		r -= households_of(g, e)
		if r < 0 {
			return e
		}
	}
	return NO_OWNER
}

// A random colony of `owner` (not a home if `no_home`), or NO_STAR.
random_colony :: proc(g: ^Game, owner: int, no_home := false) -> int {
	pick := NO_STAR
	seen := 0
	for i in 0 ..< g.star_count {
		if colony_of(g, i, owner) == nil || (no_home && is_home(g, i)) {
			continue
		}
		seen += 1
		if rng_int(&g.rng, seen) == 0 {
			pick = i
		}
	}
	return pick
}

// "Mira (Lot 6)"
lot_name :: proc(g: ^Game, b: ^Text, star: int) {
	add(b, g.stars[star].name)
	add(b, " (Lot ")
	add_int(b, star + 1)
	add(b, ")")
}

// Tells whoever should hear: the news if it is yers or in sight, and yer doormat if it is yers.
event_news :: proc(g: ^Game, owner, star: int, s: string) {
	if owner == PLAYER {
		say(g, s)
		post_notice(g, s)
	} else if star != NO_STAR && g.empires[PLAYER].sees[star] {
		say(g, s)
	}
}

// One event; false if it found nothing to happen to (another empire's luck, another day).
happen :: proc(g: ^Game, ev: Event, e: int) -> bool {
	b: Text
	switch ev {
	case .Goat:
		if g.goat.alive {
			return false
		}
		star := random_colony(g, e, true)
		if star == NO_STAR {
			star = random_colony(g, e)
		}
		if star == NO_STAR {
			return false
		}
		g.goat = {true, star, GOAT_HITS}
		add(&b, "A stray Goat turned up at ")
		lot_name(g, &b, star)
		add(&b, ". Armed ships or bases will see it off.")
		event_news(g, e, star, text(&b))
	case .Flu:
		star := random_colony(g, e)
		if star == NO_STAR {
			return false
		}
		c := any_colony(g, star)
		c.flu = FLU_TURNS
		c.flu_loss = max(1, c.households / (5 * FLU_TURNS))
		add(&b, "A Flu is going round ")
		lot_name(g, &b, star)
		add(&b, ". Expect fewer households for a while.")
		event_news(g, e, star, text(&b))
	case .Star_Out:
		star := random_colony(g, e, true)
		if star == NO_STAR {
			return false
		}
		s := &g.stars[star]
		s.colony = {}
		s.planet = .Dead
		for o in 0 ..< g.empire_count {
			if s.reports[o].filed {
				s.reports[o].planet = .Dead
			}
		}
		add(&b, "The star at ")
		lot_name(g, &b, star)
		add(&b, " has gone out, and the colony with it.")
		event_news(g, e, star, text(&b))
	case .Car:
		list: [len(Field) * TECHS_PER_FIELD]int
		n := 0
		for f in Field {
			for i in 0 ..< TECHS_PER_FIELD {
				if !g.empires[e].tech.known[f][i] {
					list[n] = tech_id(f, i)
					n += 1
				}
			}
		}
		if n == 0 {
			return false
		}
		id := list[rng_int(&g.rng, n)]
		f, i := tech_of(id)
		learn(g, e, f, i, "From a car's glovebox: ")
		if e == PLAYER {
			add(&b, "Someone left a car on the verge. In the glovebox: notes on ")
			add(&b, tech_name(id))
			add(&b, ".")
			post_notice(g, text(&b))
		}
	case .Revolt:
		star := random_colony(g, e)
		if star == NO_STAR {
			return false
		}
		any_colony(g, star).revolt = REVOLT_TURNS
		add(&b, "A Residents' Revolt at ")
		lot_name(g, &b, star)
		add(&b, ". No chores and no tax for 5 turns.")
		event_news(g, e, star, text(&b))
	case .Find:
		star := random_colony(g, e)
		if star == NO_STAR {
			return false
		}
		s := &g.stars[star]
		add(&b, "A Find in the Attic at ")
		lot_name(g, &b, star)
		if s.special == .None && rng_int(&g.rng, 2) == 0 {
			s.special = .Rich
			s.reports[e].special = .Rich
			add(&b, ": the planet turns out to be Rich.")
		} else {
			bj := FIND_MIN + rng_int(&g.rng, FIND_MAX - FIND_MIN + 1)
			g.empires[e].bj += bj
			add(&b, ": ")
			add_int(&b, bj)
			add(&b, " BJ in an old biscuit tin.")
		}
		event_news(g, e, star, text(&b))
	}
	g.events[ev] += 1
	return true
}

// The Goat: seen off by anything armed where it is, otherwise it eats, then it wanders on.
goat_turn :: proc(g: ^Game) {
	gt := &g.goat
	if !gt.alive {
		return
	}
	star := gt.star
	fire := 0
	by := NO_OWNER
	if c := any_colony(g, star); c != nil && c.bases > 0 {
		fire += c.bases * BASE_COMBAT.weapons
		by = c.owner
	}
	for &f in g.fleets {
		if f.used && f.star == star {
			for n, t in f.ships {
				if n > 0 && COMBAT[t].weapons > 0 {
					fire += n * COMBAT[t].weapons
					by = f.owner
				}
			}
		}
	}
	if fire > 0 {
		gt.hp -= fire
		if gt.hp <= 0 {
			gt.alive = false
			g.goats_seen_off += 1
			b: Text
			add(&b, "The Goat at ")
			lot_name(g, &b, star)
			add(&b, by == PLAYER ? " has been seen off by yer ships. It will not be back." : " has been seen off. It will not be back.")
			if by == PLAYER || g.empires[PLAYER].sees[star] {
				say(g, text(&b))
			}
			return
		}
	} else if c := any_colony(g, star); c != nil {
		eaten := min(GOAT_EATS, c.households - 1)
		if eaten > 0 {
			c.households -= eaten
			g.goat_ate += eaten
			if c.owner == PLAYER {
				b: Text
				add(&b, "The Goat ate ")
				add_int(&b, eaten)
				add(&b, " households at ")
				lot_name(g, &b, star)
				add(&b, ".")
				say(g, text(&b))
			}
		}
	}
	// On to one of the three nearest stars.
	near: [3]int = {NO_STAR, NO_STAR, NO_STAR}
	dist: [3]int = {max(int), max(int), max(int)}
	for i in 0 ..< g.star_count {
		if i == star || g.stars[i].wormhole {
			continue
		}
		dx, dy := g.stars[i].x - g.stars[star].x, g.stars[i].y - g.stars[star].y
		d := dx * dx + dy * dy
		for k in 0 ..< 3 {
			if d < dist[k] {
				for m := 2; m > k; m -= 1 {
					near[m], dist[m] = near[m - 1], dist[m - 1]
				}
				near[k], dist[k] = i, d
				break
			}
		}
	}
	n := 0
	for k in 0 ..< 3 {
		if near[k] != NO_STAR {
			n += 1
		}
	}
	if n > 0 {
		gt.star = near[rng_int(&g.rng, n)]
	}
}

// A colony's Flu and Revolt, at the start of its turn: false if it does nothing this turn.
colony_troubles :: proc(g: ^Game, star: int, c: ^Colony) -> bool {
	if c.flu > 0 {
		c.flu -= 1
		c.households = max(1, c.households - c.flu_loss)
		if c.flu == 0 && c.owner == PLAYER {
			b: Text
			add(&b, "The Flu at ")
			lot_name(g, &b, star)
			add(&b, " has gone round and gone.")
			say(g, text(&b))
		}
	}
	if c.revolt > 0 {
		c.revolt -= 1
		if c.revolt == 0 && c.owner == PLAYER {
			b: Text
			add(&b, "The Revolt at ")
			lot_name(g, &b, star)
			add(&b, " is over. Chores resume, grudgingly.")
			say(g, text(&b))
		}
		return false
	}
	return true
}

// An event of yers on the doormat (unless something else is there already).
post_notice :: proc(g: ^Game, s: string) {
	d := &g.doormat
	if d.waiting || d.open {
		return
	}
	d^ = {}
	d.waiting = true
	d.kind = .Notice
	add(&d.note, s)
}
