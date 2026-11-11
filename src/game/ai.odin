package game

// The computer empires (slice 1 step 5): simple and honest (PLAN.md). They see only what their own
// colonies and ships see, know only what their own Inspectors filed, obey the same fuel and range
// rules, and settle with the same Moving Vans. Each turn, before the turn runs, they set their
// sliders, choose what to build, pay their upgrade fees and send their ships. Attacking arrives with
// combat in step 6.

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
	inspectors := ships_owned(g, owner, .Inspector)
	unknown := false
	for i in 0 ..< g.star_count {
		if !g.stars[i].reports[owner].filed && !g.stars[i].wormhole_known[owner] {
			unknown = true
			break
		}
	}
	for i in 0 ..< g.star_count {
		c := colony_of(g, i, owner)
		if c == nil {
			continue
		}
		ai_sliders(g, i, c, threat)
		switch {
		case threat:
			c.build = i == e.home ? .Pickup : .Golf_Cart
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
	if c.factories >= c.households * FACTORIES_PER_HOUSEHOLD {
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
// to settle; warships and Gas Cans stay put (combat arrives in step 6).
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
nearest_unsurveyed :: proc(g: ^Game, owner, from: int, taken: ^[MAX_STARS]bool) -> int {
	best, best_d := NO_STAR, max(int)
	a := g.stars[from]
	for i in 0 ..< g.star_count {
		s := &g.stars[i]
		if i == from || s.reports[owner].filed || s.wormhole_known[owner] || taken[i] {
			continue
		}
		if send_problem(g, owner, from, i, ship_one(.Inspector)) != "" {
			continue
		}
		// Only a trip that leaves fuel enough to get back to a colony afterwards.
		if src := fleet_of(g, from, owner); src != nil {
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
