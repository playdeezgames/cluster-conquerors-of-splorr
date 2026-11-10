package game

// Ships, fleets, travel, fuel and surveying (slice 1 step 2). All yer ships at one star are one fleet;
// ships sent off together are one fleet in transit until they arrive and join whatever is there.

Ship_Type :: enum u8 {
	Inspector, // scout; surveys every star it arrives at
	Moving_Van, // colony ship (founding arrives in step 3)
	Carpool, // troop transport (step 7)
	Gas_Can, // tanker
	Golf_Cart, // small warship
	Pickup, // medium warship
	Monster_Truck, // large warship
}

Ship_Info :: struct {
	name:  string,
	cost:  int, // BJ of production (building arrives in step 3)
	fuel:  int, // turns it can spend away from a refuelling place
	speed: int, // cells a turn
}

// Starting values from PLAN.md; speeds are Claude's (not in the plan), for review.
SHIPS := [Ship_Type]Ship_Info {
	.Inspector     = {"Inspector", 10, 6, 4},
	.Moving_Van    = {"Moving Van", 60, 4, 2},
	.Carpool       = {"Carpool", 20, 4, 3},
	.Gas_Can       = {"Gas Can", 25, 8, 3},
	.Golf_Cart     = {"Golf Cart", 20, 4, 4},
	.Pickup        = {"Pickup", 50, 4, 3},
	.Monster_Truck = {"Monster Truck", 120, 3, 2},
}

GAS_CAN_REFILLS :: 10 // refills each Gas Can carries when filled at a colony

// The starting fleet at home.
START_SHIPS := [Ship_Type]int {
	.Inspector     = 2,
	.Moving_Van    = 1,
	.Carpool       = 0,
	.Gas_Can       = 1,
	.Golf_Cart     = 2,
	.Pickup        = 0,
	.Monster_Truck = 0,
}

// Survey lies (PLAN.md starting rates).
BAD_READING_PERCENT :: 15 // a report misstates the planet's type or size
FAKE_SPECIAL_IN :: 6 // a star with no special is reported Rich or Ancient Artifacts one time in this many
MISFILE_PER_MILLE :: 10 // each turn, each filed report (not home's) is lost this often in 1000

MAX_FLEETS :: 64

Fleet :: struct {
	used:    bool,
	ships:   [Ship_Type]int,
	star:    int, // docked at this star, or NO_STAR while in transit
	from:    int, // in transit: from this star ...
	to:      int, // ... to this one
	left:    int, // turns still to go
	total:   int, // turns the trip takes
	away:    int, // turns spent away from a refuelling place
	refills: int, // what its Gas Cans still carry
}

// What an Inspector filed about a star; it may be wrong (see the lies above), and it can be lost.
Report :: struct {
	filed:   bool,
	planet:  Planet_Type,
	size:    Planet_Size,
	special: Special,
}

fleet_size :: proc(f: ^Fleet) -> int {
	n := 0
	for c in f.ships {
		n += c
	}
	return n
}

// The fewest turns away any ship in it can manage.
fleet_fuel :: proc(f: ^Fleet) -> int {
	best := max(int)
	for c, t in f.ships {
		if c > 0 {
			best = min(best, SHIPS[t].fuel)
		}
	}
	return best == max(int) ? 0 : best
}

// The slowest ship sets the pace.
fleet_speed :: proc(f: ^Fleet) -> int {
	best := max(int)
	for c, t in f.ships {
		if c > 0 {
			best = min(best, SHIPS[t].speed)
		}
	}
	return best == max(int) ? 1 : best
}

// Turns of fuel still in the tanks.
fleet_range :: proc(f: ^Fleet) -> int {
	return max(0, fleet_fuel(f) - f.away)
}

// A fleet with no fuel left, away from anywhere to refuel. It waits.
stranded :: proc(g: ^Game, f: ^Fleet) -> bool {
	return f.star != NO_STAR && !refuels_at(g, f.star) && fleet_range(f) == 0
}

// Where yer ships fill up: yer colonies (only home until step 3).
refuels_at :: proc(g: ^Game, star: int) -> bool {
	return star == g.home
}

// Turns from one star to another at a speed: the fewest whole turns that cover the distance.
trip_turns :: proc(g: ^Game, from, to, speed: int) -> int {
	a, b := g.stars[from], g.stars[to]
	d2 := (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
	t := 1
	for (t * speed) * (t * speed) < d2 {
		t += 1
	}
	return t
}

// Yer fleet docked at a star, or nil.
fleet_at :: proc(g: ^Game, star: int) -> ^Fleet {
	for &f in g.fleets {
		if f.used && f.star == star {
			return &f
		}
	}
	return nil
}

new_fleet :: proc(g: ^Game) -> ^Fleet {
	for &f in g.fleets {
		if !f.used {
			f = {
				used = true,
				star = NO_STAR,
				from = NO_STAR,
				to   = NO_STAR,
			}
			return &f
		}
	}
	return nil
}

// Puts a fleet down at a star, joining any fleet already there (the joined fleet goes as far as its
// emptiest tank, so it keeps the larger `away`).
dock :: proc(g: ^Game, f: ^Fleet, star: int) {
	f.star, f.from, f.to, f.left, f.total = star, NO_STAR, NO_STAR, 0, 0
	for &o in g.fleets {
		if o.used && &o != f && o.star == star {
			for c, t in f.ships {
				o.ships[t] += c
			}
			o.away = max(o.away, f.away)
			o.refills += f.refills
			f^ = {}
			return
		}
	}
}

// Why a fleet cannot be sent from `from` to `to` with these ships, or "" if it can.
send_problem :: proc(g: ^Game, from, to: int, ships: [Ship_Type]int) -> string {
	if to == from {
		return "They are already here."
	}
	trial := Fleet {
		ships = ships,
	}
	if fleet_size(&trial) == 0 {
		return "Nobody is going."
	}
	f := fleet_at(g, from)
	if f == nil {
		return "Nobody is here."
	}
	trial.away = f.away
	if trip_turns(g, from, to, fleet_speed(&trial)) > fleet_range(&trial) {
		return "Out of range."
	}
	return ""
}

// Sends some of the ships at `from` towards `to`. The caller has checked send_problem.
send_fleet :: proc(g: ^Game, from, to: int, ships: [Ship_Type]int) {
	src := fleet_at(g, from)
	f := new_fleet(g)
	if src == nil || f == nil {
		return
	}
	cans := src.ships[.Gas_Can]
	f.ships = ships
	f.away = src.away
	if cans > 0 {
		f.refills = src.refills * ships[.Gas_Can] / cans
		src.refills -= f.refills
	}
	for c, t in ships {
		src.ships[t] -= c
	}
	if fleet_size(src) == 0 {
		src^ = {}
	}
	f.from, f.to = from, to
	f.total = trip_turns(g, from, to, fleet_speed(f))
	f.left = f.total
}

// Moves every fleet a turn, deals with arrivals, burns and refills fuel, and loses paperwork.
end_turn :: proc(g: ^Game) {
	for &f in g.fleets {
		if !f.used || f.star != NO_STAR {
			continue
		}
		f.left -= 1
		if f.left <= 0 {
			arrive(g, &f, f.to)
		}
	}
	for &f in g.fleets {
		if !f.used {
			continue
		}
		was_stranded := stranded(g, &f)
		if f.star != NO_STAR && refuels_at(g, f.star) {
			f.away = 0
			f.refills = f.ships[.Gas_Can] * GAS_CAN_REFILLS
			continue
		}
		f.away += 1
		if f.star != NO_STAR && f.away > 0 && f.refills > 0 && f.ships[.Gas_Can] > 0 {
			f.away = 0
			f.refills -= 1
			if was_stranded {
				b: Text
				add(&b, "The Gas Can at Lot ")
				add_int(&b, f.star + 1)
				add(&b, " fills everyone up. ")
				add_int(&b, f.refills)
				add(&b, " refills left.")
				say(g, text(&b))
			}
			continue
		}
		if !was_stranded && stranded(g, &f) {
			b: Text
			add(&b, "Yer ships at Lot ")
			add_int(&b, f.star + 1)
			add(&b, " are out of fuel. They will wait for a Gas Can.")
			say(g, text(&b))
		}
	}
	for i in 0 ..< g.star_count {
		r := &g.stars[i].report
		if i != g.home && r.filed && rng_int(&g.rng, 1000) < MISFILE_PER_MILLE {
			r^ = {}
			b: Text
			add(&b, "The survey of Lot ")
			add_int(&b, i + 1)
			add(&b, " has been misfiled.")
			say(g, text(&b))
		}
	}
}

// A fleet reaches a star: a wormhole throws it somewhere else; an Inspector files a survey.
arrive :: proc(g: ^Game, f: ^Fleet, star: int) {
	at := star
	s := &g.stars[at]
	if s.wormhole {
		s.wormhole_known = true
		for {
			at = rng_int(&g.rng, g.star_count)
			if !g.stars[at].wormhole {
				break
			}
		}
		b: Text
		add(&b, "Lot ")
		add_int(&b, star + 1)
		add(&b, " was a wormhole. Yer ships came out at Lot ")
		add_int(&b, at + 1)
		add(&b, ".")
		say(g, text(&b))
	}
	if f.ships[.Inspector] > 0 && at != g.home {
		survey(g, at)
	}
	dock(g, f, at)
}

// Files a fresh report on a star, which may be wrong in the ways the plan allows.
survey :: proc(g: ^Game, i: int) {
	s := &g.stars[i]
	r := Report {
		filed   = true,
		planet  = s.planet,
		size    = s.size,
		special = s.special,
	}
	if rng_int(&g.rng, 100) < BAD_READING_PERCENT {
		if rng_int(&g.rng, 2) == 0 {
			r.planet = Planet_Type((int(s.planet) + 1 + rng_int(&g.rng, len(Planet_Type) - 1)) % len(Planet_Type))
		} else {
			r.size = Planet_Size((int(s.size) + 1 + rng_int(&g.rng, 2)) % 3)
		}
	}
	if s.special == .None && rng_int(&g.rng, FAKE_SPECIAL_IN) == 0 {
		r.special = rng_int(&g.rng, 2) == 0 ? .Rich : .Artifacts
	}
	s.report = r
	b: Text
	add(&b, "Survey filed: ")
	add(&b, s.name)
	add(&b, " (Lot ")
	add_int(&b, i + 1)
	add(&b, "), ")
	describe_report(&b, &s.report)
	say(g, text(&b))
}

// "a Rich, Large Ocean world." from a report.
describe_report :: proc(b: ^Text, r: ^Report) {
	first := r.special != .None ? SPECIAL_NAMES[r.special] : SIZE_NAMES[r.size]
	add(b, first[0] == 'A' || first[0] == 'O' || first[0] == 'E' || first[0] == 'I' ? "an " : "a ")
	if r.special != .None {
		add(b, SPECIAL_NAMES[r.special])
		add(b, ", ")
	}
	add(b, SIZE_NAMES[r.size])
	add(b, " ")
	add(b, PLANET_NAMES[r.planet])
	add(b, " world.")
}
