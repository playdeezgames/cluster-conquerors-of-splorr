package game

import "core:slice"

// Colonies (slice 1 step 3): households, factories, waste, defence bases and the five HOA-chore
// sliders that share each colony's production, as in Master of Orion. A tenth goes to BJ first.
// All numbers are starting values to tune by playing (PLAN.md).

Chore :: enum u8 {
	Parking, // builds the colony's ship order
	Fencing, // builds defence bases (they fight in step 6)
	Home_Improvement, // builds factories
	Lawn_Care, // cleans waste; what is left over helps households grow
	Book_Club, // research points (spent in step 4)
}

CHORE_NAMES := [Chore]string {
	.Parking          = "Parking",
	.Fencing          = "Fencing",
	.Home_Improvement = "Home Improvement",
	.Lawn_Care        = "Lawn Care",
	.Book_Club        = "Book Club",
}

TAX_PERCENT :: 10 // of production, to BJ, before the sliders share the rest
FACTORY_COST :: 10 // production per factory
FACTORIES_PER_HOUSEHOLD :: 2 // a colony can use this many factories per household
BASE_COST :: 30 // production per defence base
WASTE_PER_FACTORIES :: 4 // one waste a turn for every this many factories
WASTE_CLEANED_PER_POINT :: 2 // one point of Lawn Care cleans this much waste
WASTE_TO_SHRINK :: 10 // waste left lying about this long takes a household off the planet's maximum
GROWTH_PER_POINT :: 10 // spare Lawn Care points per extra household
SPECIAL_FOUND_OUT :: 3 // turns before a new colony finds out whether its special was real
NEW_COLONY_HOUSEHOLDS :: 2
HOME_HOUSEHOLDS :: 50 // the home world starts settled (Master of Orion's start)
HOME_FACTORIES :: 30

// Households a planet holds, by size, before its type is counted.
SIZE_HOUSEHOLDS := [Planet_Size]int {
	.Small  = 40,
	.Medium = 70,
	.Large  = 100,
}

// Percent of the size's households each type holds; 0 means it cannot be settled yet (Landscaping,
// in step 4, opens the hostile ones).
TYPE_PERCENT := [Planet_Type]int {
	.Garden   = 125,
	.Terran   = 100,
	.Ocean    = 90,
	.Jungle   = 90,
	.Arid     = 80,
	.Steppe   = 80,
	.Desert   = 70,
	.Tundra   = 70,
	.Barren   = 0,
	.Dead     = 0,
	.Inferno  = 0,
	.Toxic    = 0,
	.Radiated = 0,
}

Colony :: struct {
	owned:     bool,
	households: int,
	wear:      int, // households of room that waste has taken off the planet
	factories: int,
	bases:     int,
	waste:     int, // uncleaned waste
	age:       int, // turns since founding
	slider:    [Chore]int, // percent of what is left after tax; sums to 100
	locked:    [Chore]bool,
	build:     Ship_Type, // what Parking builds
	stored:    [Chore]int, // production put by towards the next ship, base or factory
}

HOME_SLIDERS := [Chore]int {
	.Parking          = 20,
	.Fencing          = 0,
	.Home_Improvement = 50,
	.Lawn_Care        = 10,
	.Book_Club        = 20,
}

NEW_SLIDERS := [Chore]int {
	.Parking          = 0,
	.Fencing          = 0,
	.Home_Improvement = 60,
	.Lawn_Care        = 20,
	.Book_Club        = 20,
}

// Percent of the size's households a hostile type holds once Landscaping lets it be settled.
HOSTILE_PERCENT := [Planet_Type]int {
	.Garden   = 0,
	.Terran   = 0,
	.Ocean    = 0,
	.Jungle   = 0,
	.Arid     = 0,
	.Steppe   = 0,
	.Desert   = 0,
	.Tundra   = 0,
	.Barren   = 50,
	.Dead     = 40,
	.Inferno  = 30,
	.Toxic    = 30,
	.Radiated = 30,
}

// Households a planet holds with what yer Landscaping knows; 0 if it cannot be settled yet.
planet_max :: proc(g: ^Game, planet: Planet_Type, size: Planet_Size) -> int {
	if !can_settle(g, planet) {
		return 0
	}
	pct := TYPE_PERCENT[planet] > 0 ? TYPE_PERCENT[planet] : HOSTILE_PERCENT[planet]
	return SIZE_HOUSEHOLDS[size] * pct * (100 + bonus(g, .Households)) / 10000
}

// A colony's room: the planet's, less what waste has worn away.
colony_max :: proc(g: ^Game, star: int) -> int {
	s := &g.stars[star]
	return max(1, planet_max(g, s.planet, s.size) - s.colony.wear)
}

factory_cost :: proc(g: ^Game) -> int {
	return max(4, FACTORY_COST - bonus(g, .Factory_Cost))
}

colony_at :: proc(g: ^Game, star: int) -> ^Colony {
	c := &g.stars[star].colony
	return c.owned ? c : nil
}

found_colony :: proc(g: ^Game, star: int, households: int) -> ^Colony {
	s := &g.stars[star]
	s.colony = {
		owned      = true,
		households = households,
		slider     = NEW_SLIDERS,
		build      = .Inspector,
	}
	return &s.colony
}

// What a colony makes in a turn: half a point per household, a point per worked factory, more on a
// Rich world and less on a Poor one.
production :: proc(g: ^Game, star: int) -> int {
	c := colony_at(g, star)
	if c == nil {
		return 0
	}
	p := c.households / 2 + min(c.factories, c.households)
	#partial switch g.stars[star].special {
	case .Rich:
		p = p * 3 / 2
	case .Poor:
		p = p / 2
	}
	return p
}

tax :: proc(g: ^Game, star: int) -> int {
	return production(g, star) * TAX_PERCENT / 100
}

// Production a chore gets this turn.
chore_points :: proc(g: ^Game, star: int, ch: Chore) -> int {
	c := colony_at(g, star)
	if c == nil {
		return 0
	}
	p := production(g, star)
	return (p - p * TAX_PERCENT / 100) * c.slider[ch] / 100
}

// Research points: Book Club, doubled by Ancient Artifacts.
research_points :: proc(g: ^Game, star: int) -> int {
	r := chore_points(g, star, .Book_Club)
	if g.stars[star].special == .Artifacts {
		r *= 2
	}
	return r
}

waste_made :: proc(g: ^Game, c: ^Colony) -> int {
	return c.factories / (WASTE_PER_FACTORIES * (1 + bonus(g, .Less_Waste)))
}

// Sets one slider and shares out the rest among the unlocked others in proportion to what they had
// (evenly if they had nothing), so the five always add up to 100. A locked slider does not move.
set_slider :: proc(c: ^Colony, ch: Chore, value: int) {
	set_share(slice.enumerated_array(&c.slider), slice.enumerated_array(&c.locked), int(ch), value)
}

// The sharing behind every set of sliders (a colony's chores, the research fields).
set_share :: proc(values: []int, locked: []bool, ch: int, value: int) {
	if locked[ch] {
		return
	}
	locked_sum := 0
	free_others := 0
	free_sum := 0
	for v, o in values {
		if o == ch {
			continue
		}
		if locked[o] {
			locked_sum += v
		} else {
			free_others += 1
			free_sum += v
		}
	}
	if free_others == 0 {
		values[ch] = 100 - locked_sum
		return
	}
	v := clamp(value, 0, 100 - locked_sum)
	rest := 100 - locked_sum - v
	values[ch] = v
	given := 0
	last := ch
	for o in 0 ..< len(values) {
		if o == ch || locked[o] {
			continue
		}
		share := free_sum > 0 ? rest * values[o] / free_sum : rest / free_others
		values[o] = share
		given += share
		last = o
	}
	// Rounding leftovers go to the largest free slider (the last one if they are equal).
	if given != rest {
		big := last
		for o in 0 ..< len(values) {
			if o != ch && !locked[o] && values[o] > values[big] {
				big = o
			}
		}
		values[big] += rest - given
	}
}

// One turn of a colony: tax, then each chore spends its share.
run_colony :: proc(g: ^Game, star: int) {
	c := colony_at(g, star)
	if c == nil {
		return
	}
	s := &g.stars[star]
	g.bj += tax(g, star)
	g.research += research_points(g, star)

	// Home Improvement: factories, up to what the households can work; the surplus goes to BJ.
	c.stored[.Home_Improvement] += chore_points(g, star, .Home_Improvement)
	cap := c.households * FACTORIES_PER_HOUSEHOLD
	for c.stored[.Home_Improvement] >= factory_cost(g) && c.factories < cap {
		c.stored[.Home_Improvement] -= factory_cost(g)
		c.factories += 1
	}
	if c.factories >= cap {
		g.bj += c.stored[.Home_Improvement]
		c.stored[.Home_Improvement] = 0
	}

	// Fencing: defence bases.
	c.stored[.Fencing] += chore_points(g, star, .Fencing)
	for c.stored[.Fencing] >= BASE_COST {
		c.stored[.Fencing] -= BASE_COST
		c.bases += 1
	}

	// Lawn Care: clean this turn's waste; spare points help households grow; uncleaned waste wears the
	// planet down.
	care := chore_points(g, star, .Lawn_Care)
	c.waste += waste_made(g, c)
	cleaned := min(c.waste, care * WASTE_CLEANED_PER_POINT)
	c.waste -= cleaned
	spare := care - (cleaned + WASTE_CLEANED_PER_POINT - 1) / WASTE_CLEANED_PER_POINT
	for c.waste >= WASTE_TO_SHRINK {
		c.waste -= WASTE_TO_SHRINK
		c.wear += 1
		b: Text
		add(&b, "Complaint: yards at ")
		add(&b, s.name)
		add(&b, " (Lot ")
		add_int(&b, star + 1)
		add(&b, ") are a mess. Room for one household fewer.")
		say(g, text(&b))
	}

	// Households grow towards the maximum (slower as it fills), plus whatever spare Lawn Care buys.
	room := colony_max(g, star)
	if c.households < room {
		grow := 1 + c.households * (room - c.households) / (room * 8)
		grow += spare / GROWTH_PER_POINT
		c.households = min(room, c.households + grow)
	} else if c.households > room {
		c.households = room
	}

	// Parking: the ship order. Ships appear at the colony and join yer fleet there.
	c.stored[.Parking] += chore_points(g, star, .Parking)
	cost := SHIPS[c.build].cost
	for c.stored[.Parking] >= cost {
		c.stored[.Parking] -= cost
		f := new_fleet(g)
		if f == nil {
			break
		}
		f.ships[c.build] = 1
		f.kit = empire_kit(g)
		f.refills = c.build == .Gas_Can ? GAS_CAN_REFILLS : 0
		dock(g, f, star)
		b: Text
		add(&b, "A new ")
		add(&b, SHIPS[c.build].name)
		add(&b, " is parked at ")
		add(&b, s.name)
		add(&b, " (Lot ")
		add_int(&b, star + 1)
		add(&b, ").")
		say(g, text(&b))
	}

	// A new colony finds out about its special after a few turns.
	c.age += 1
	if c.age == SPECIAL_FOUND_OUT && s.report.special != s.special {
		b: Text
		add(&b, s.name)
		add(&b, " (Lot ")
		add_int(&b, star + 1)
		if s.special == .None {
			add(&b, ") turns out not to be ")
			add(&b, SPECIAL_NAMES[s.report.special])
			add(&b, ". The listing was optimistic.")
		} else {
			add(&b, ") turns out to be ")
			add(&b, SPECIAL_NAMES[s.special])
			add(&b, ".")
		}
		say(g, text(&b))
		s.report.special = s.special
	}
}

// A Moving Van reaches a star: the movers see the planet as it is, and settle it if they can.
movers_arrive :: proc(g: ^Game, f: ^Fleet, star: int) {
	s := &g.stars[star]
	if f.ships[.Moving_Van] == 0 || s.wormhole || colony_at(g, star) != nil {
		return
	}
	special := s.report.filed ? s.report.special : Special.None
	s.report = {
		filed   = true,
		planet  = s.planet,
		size    = s.size,
		special = special,
	}
	b: Text
	if !can_settle(g, s.planet) {
		add(&b, "The movers took one look at ")
		add(&b, s.name)
		add(&b, " (Lot ")
		add_int(&b, star + 1)
		add(&b, "): a ")
		add(&b, PLANET_NAMES[s.planet])
		add(&b, " world. They are waiting in the van.")
		say(g, text(&b))
		return
	}
	f.ships[.Moving_Van] -= 1
	found_colony(g, star, NEW_COLONY_HOUSEHOLDS)
	add(&b, "The movers have unpacked at ")
	add(&b, s.name)
	add(&b, " (Lot ")
	add_int(&b, star + 1)
	add(&b, "), a ")
	add(&b, SIZE_NAMES[s.size])
	add(&b, " ")
	add(&b, PLANET_NAMES[s.planet])
	add(&b, " world. Welcome to the neighbourhood.")
	say(g, text(&b))
}
