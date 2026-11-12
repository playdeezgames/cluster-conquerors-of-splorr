package game

// The computer empires (slice 1 step 5): simple and honest (PLAN.md). They see only what their own
// colonies and ships see, know only what their own Inspectors filed, obey the same fuel and range
// rules, and settle with the same Moving Vans. Each turn, before the turn runs, they set their
// sliders, choose what to build, pay their upgrade fees, send their ships, and attack where they saw
// something weaker than themselves.

THREAT_RANGE :: 10 // cells: a hostile fleet this close to a colony means build warships

ai_turn :: proc(g: ^Game, owner: int) {
	e := &g.empires[owner]
	for &f in g.fleets {
		if f.used && f.owner == owner {
			pay_upgrades(g, &f)
		}
	}
	threat := threatened(g, owner)
	have_van := ships_owned(g, owner, .Moving_Van) > 0
	target_exists := best_settle_target(g, owner, e.home, nil) != NO_STAR
	inspectors := 0 // Inspectors that can still fly
	for &f in g.fleets {
		if f.used && f.owner == owner && !stranded(g, &f) {
			inspectors += f.ships[.Inspector]
		}
	}
	unknown := false
	for i in 0 ..< g.star_count {
		if !g.stars[i].reports[owner].filed && !g.stars[i].wormhole_known[owner] {
			unknown = true
			break
		}
	}
	prey, need, base := invasion_target(g, owner)
	carpools := ships_owned(g, owner, .Carpool)
	for i in 0 ..< g.star_count {
		c := colony_of(g, i, owner)
		if c == nil {
			continue
		}
		ai_sliders(g, i, c, threat)
		switch {
		case threat:
			c.build = i == e.home ? .Pickup : .Golf_Cart
		case prey != NO_STAR && i == base && carpools < need:
			c.build = .Carpool
		case !have_van && target_exists:
			c.build = .Moving_Van
			have_van = true // one colony at a time builds the next van
		case inspectors < 2 && unknown:
			c.build = .Inspector
			inspectors += 1
		case:
			c.build = .Golf_Cart
		}
	}
	ai_fleets(g, owner)
	if !threat {
		ai_attack(g, owner)
		if prey != NO_STAR {
			ai_invade(g, owner, base, prey, need)
		}
	}
}

// The nearest pair of one of the empire's colonies big enough to spare Carpools and an enemy colony it
// remembers with nothing left to defend it, in a Carpool's reach; and how many Carpools it would want
// (half as many troops again as the colony's militia).
invasion_target :: proc(g: ^Game, owner: int) -> (target, need, base: int) {
	e := &g.empires[owner]
	target, base = NO_STAR, NO_STAR
	best_grudge, best_d := -1, max(int)
	trial := Fleet {
		ships = ship_one(.Carpool),
	}
	for from in 0 ..< g.star_count {
		c := colony_of(g, from, owner)
		if c == nil || c.households <= CARPOOL_LOAD * 2 {
			continue
		}
		for t in 0 ..< g.star_count {
			in_ := e.intel[t]
			if !in_.seen || in_.owner == NO_OWNER || in_.owner == owner || in_.strength > 0 {
				continue
			}
			if trip_turns(g, from, t, fleet_speed(&trial)) > fleet_range(&trial) {
				continue
			}
			a, b := g.stars[from], g.stars[t]
			d := (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
			gr := grudge_at(g, owner, in_)
			if gr > best_grudge || (gr == best_grudge && d < best_d) {
				target, base, best_grudge, best_d = t, from, gr, d
				militia := militia_of(in_.households)
				need = (militia * 3 / 2) / CARPOOL_LOAD + 1
			}
		}
	}
	return
}

// Sends the Carpools at the launching colony once there are enough of them.
ai_invade :: proc(g: ^Game, owner, home, target, need: int) {
	f := fleet_of(g, home, owner)
	if f == nil || f.ships[.Carpool] < need {
		return
	}
	cars := ship_n(.Carpool, f.ships[.Carpool])
	if send_problem(g, owner, home, target, cars) == "" {
		send_fleet(g, owner, home, target, cars)
	}
}

ATTACK_PERCENT :: 150 // a computer empire attacks only with at least this share of the hits it saw there

warship_hits :: proc(f: ^Fleet) -> int {
	n := 0
	for c, t in f.ships {
		if COMBAT[t].weapons > 0 {
			n += c * COMBAT[t].hp
		}
	}
	return n
}

warships_of :: proc(f: ^Fleet) -> (ships: [Ship_Type]int) {
	for c, t in f.ships {
		if COMBAT[t].weapons > 0 {
			ships[t] = c
		}
	}
	return
}

// Warships at a colony go after the nearest enemy colony or fleet they remember seeing, if they are
// clearly stronger than what they saw there and can reach it; warships idling away from home with
// nothing to fight come home.
ai_attack :: proc(g: ^Game, owner: int) {
	e := &g.empires[owner]
	for i in 0 ..< g.star_count {
		f := fleet_of(g, i, owner)
		if f == nil || stranded(g, f) || warship_hits(f) == 0 {
			continue
		}
		if colony_of(g, i, owner) == nil {
			if strength_at(g, i, owner) == 0 {
				go_home(g, owner, i, warships_of(f))
			}
			continue
		}
		mine := warship_hits(f)
		best, best_grudge, best_d := NO_STAR, -1, max(int)
		for t in 0 ..< g.star_count {
			in_ := e.intel[t]
			if t == g.clubhouse && g.moth_alive && !in_.seen {
				in_ = {seen = true, owner = NO_OWNER, strength = MOTH_COMBAT.hp} // the legend everyone has heard
			}
			if t == i || !in_.seen || in_.strength == 0 {
				continue
			}
			if in_.owner == owner || mine * 100 < ATTACK_PERCENT * in_.strength {
				continue
			}
			if send_problem(g, owner, i, t, warships_of(f)) != "" {
				continue
			}
			a, b := g.stars[i], g.stars[t]
			d := (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
			gr := grudge_at(g, owner, in_)
			if gr > best_grudge || (gr == best_grudge && d < best_d) {
				best, best_grudge, best_d = t, gr, d
			}
		}
		if best != NO_STAR {
			send_fleet(g, owner, i, best, warships_of(f))
		}
	}
}

// Rules of thumb: enough Lawn Care to stay tidy, a fifth to Book Club, ships when threatened or once
// a colony is grown, the rest to Home Improvement until the factories are full.
ai_sliders :: proc(g: ^Game, star: int, c: ^Colony, threat: bool) {
	after_tax := production(g, star) - tax(g, star)
	need := (c.waste + waste_made(g, c) + WASTE_CLEANED_PER_POINT - 1) / WASTE_CLEANED_PER_POINT
	care := 5
	if after_tax > 0 {
		care = clamp(need * 100 / after_tax + 5, 5, 40)
	}
	parking := 20
	fencing := 0
	if threat {
		parking, fencing = 35, 10
	} else if c.households < 10 {
		parking = 0
	}
	books := 20
	improve := 100 - care - parking - fencing - books
	if c.factories >= factory_cap(c) {
		books += improve
		improve = 0
	}
	if improve < 0 {
		parking += improve
		improve = 0
	}
	c.slider = {
		.Parking          = parking,
		.Fencing          = fencing,
		.Home_Improvement = improve,
		.Lawn_Care        = care,
		.Book_Club        = books,
	}
	c.locked = {}
}

// A hostile fleet the empire can see near one of its colonies.
threatened :: proc(g: ^Game, owner: int) -> bool {
	for &f in g.fleets {
		if !f.used || f.owner == owner {
			continue
		}
		fx, fy := fleet_cell(g, &f)
		seen := false
		if f.star != NO_STAR {
			seen = g.empires[owner].sees[f.star]
		} else {
			seen = sees_cell(g, owner, &f)
		}
		if !seen {
			continue
		}
		for i in 0 ..< g.star_count {
			if colony_of(g, i, owner) == nil {
				continue
			}
			dx, dy := g.stars[i].x - fx, g.stars[i].y - fy
			if dx * dx + dy * dy <= THREAT_RANGE * THREAT_RANGE {
				return true
			}
		}
	}
	return false
}

ships_owned :: proc(g: ^Game, owner: int, t: Ship_Type) -> int {
	n := 0
	for &f in g.fleets {
		if f.used && f.owner == owner {
			n += f.ships[t]
		}
	}
	return n
}

// The best star to send a Moving Van to from `from`, by what the empire believes: a settleable world
// with room, no colony seen there, not already someone's destination, and in the van's reach.
best_settle_target :: proc(g: ^Game, owner, from: int, taken: ^[MAX_STARS]bool) -> int {
	e := &g.empires[owner]
	best, best_score := NO_STAR, 0
	for i in 0 ..< g.star_count {
		s := &g.stars[i]
		r := &s.reports[owner]
		if !r.filed || s.wormhole_known[owner] || (taken != nil && taken[i]) {
			continue
		}
		if i == g.clubhouse && g.moth_alive {
			continue // everyone has heard about the moth
		}
		if e.sees[i] && any_colony(g, i) != nil {
			continue
		}
		room := planet_max(g, owner, r.planet, r.size)
		if room == 0 {
			continue
		}
		a, b := g.stars[from], s^
		d := isqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
		score := room * 100 / (d + 5)
		if score > best_score {
			best, best_score = i, score
		}
	}
	return best
}

// Inspectors go to the nearest star nobody of theirs has surveyed; Moving Vans go to the best place
// to settle; Gas Cans stay put (warships are ai_attack's).
ai_fleets :: proc(g: ^Game, owner: int) {
	taken: [MAX_STARS]bool
	for &f in g.fleets {
		if f.used && f.owner == owner && f.star == NO_STAR {
			taken[f.to] = true
		}
	}
	for i in 0 ..< g.star_count {
		f := fleet_of(g, i, owner)
		if f == nil || stranded(g, f) {
			continue
		}
		for f != nil && f.ships[.Inspector] > 0 {
			to := nearest_unsurveyed(g, owner, i, &taken)
			if to == NO_STAR && colony_of(g, i, owner) != nil && f.ships[.Inspector] > 1 {
				// Nothing left within a round trip: one goes one way, as a probe. Stranded, it still sees.
				to = nearest_unsurveyed(g, owner, i, &taken, one_way = true)
			}
			if to == NO_STAR {
				break
			}
			taken[to] = true
			send_fleet(g, owner, i, to, ship_one(.Inspector))
			f = fleet_of(g, i, owner)
		}
		// Inspectors with nowhere left to go from here come home to fill up.
		if f != nil && f.ships[.Inspector] > 0 && colony_of(g, i, owner) == nil {
			go_home(g, owner, i, ship_n(.Inspector, f.ships[.Inspector]))
			f = fleet_of(g, i, owner)
		}
		if f != nil && f.ships[.Moving_Van] > 0 {
			to := best_settle_target(g, owner, i, &taken)
			if to != NO_STAR && send_problem(g, owner, i, to, ship_one(.Moving_Van)) == "" {
				taken[to] = true
				send_fleet(g, owner, i, to, ship_one(.Moving_Van))
			} else if colony_of(g, i, owner) == nil {
				go_home(g, owner, i, ship_n(.Moving_Van, f.ships[.Moving_Van]))
			}
		}
	}
}

// The empire's nearest colony to a star (by straight distance), or NO_STAR.
nearest_colony :: proc(g: ^Game, owner, from: int) -> int {
	best, best_d := NO_STAR, max(int)
	a := g.stars[from]
	for i in 0 ..< g.star_count {
		if colony_of(g, i, owner) == nil {
			continue
		}
		s := g.stars[i]
		d := (a.x - s.x) * (a.x - s.x) + (a.y - s.y) * (a.y - s.y)
		if d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

// Sends these ships from `from` to the nearest colony they can reach.
go_home :: proc(g: ^Game, owner, from: int, ships: [Ship_Type]int) {
	to := nearest_colony(g, owner, from)
	if to != NO_STAR && to != from && send_problem(g, owner, from, to, ships) == "" {
		send_fleet(g, owner, from, to, ships)
	}
}

ship_one :: proc(t: Ship_Type) -> [Ship_Type]int {
	return ship_n(t, 1)
}

ship_n :: proc(t: Ship_Type, n: int) -> (ships: [Ship_Type]int) {
	ships[t] = n
	return
}

// The closest star an Inspector from `from` can reach, and come back from, that the empire has no
// report on.
nearest_unsurveyed :: proc(g: ^Game, owner, from: int, taken: ^[MAX_STARS]bool, one_way := false) -> int {
	best, best_d := NO_STAR, max(int)
	a := g.stars[from]
	for i in 0 ..< g.star_count {
		s := &g.stars[i]
		if i == from || s.reports[owner].filed || s.wormhole_known[owner] || taken[i] {
			continue
		}
		if i == g.clubhouse && g.moth_alive {
			continue
		}
		if send_problem(g, owner, from, i, ship_one(.Inspector)) != "" {
			continue
		}
		// Only a trip that leaves fuel enough to get back to a colony afterwards (unless one way).
		if src := fleet_of(g, from, owner); src != nil && !one_way {
			trial := Fleet {
				ships = ship_one(.Inspector),
				away  = src.away,
				kit   = src.kit,
			}
			speed := fleet_speed(&trial)
			back := nearest_colony(g, owner, i)
			there := trip_turns(g, from, i, speed)
			home_trip := back == NO_STAR ? 0 : trip_turns(g, i, back, speed)
			if there + home_trip > fleet_range(&trial) {
				continue
			}
		}
		d := (a.x - s.x) * (a.x - s.x) + (a.y - s.y) * (a.y - s.y)
		if d < best_d {
			best, best_d = i, d
		}
	}
	return best
}
