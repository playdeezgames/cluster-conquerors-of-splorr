package game

import "core:slice"

// Technology (slice 1 step 4): six fields of HOA hobbies, eight techs in each, of which a random five
// are on offer in any one game (as in Master of Orion, nobody gets everything). Book Club's research
// is shared among the fields by six empire-wide sliders; each field works through its cheapest offered
// tech. Numbers are starting values to tune by playing (PLAN.md).

Field :: enum u8 {
	Spreadsheets, // computers: to-hit, survey accuracy
	Renovation, // construction: armour, cheaper factories
	Fences, // force fields: shields, defence bases
	Landscaping, // planetology: settling hostile worlds, more households, less waste
	Commuting, // propulsion: speed, fuel
	Disputes, // weapons
}

FIELD_NAMES := [Field]string {
	.Spreadsheets = "Spreadsheets",
	.Renovation   = "Renovation",
	.Fences       = "Fences",
	.Landscaping  = "Landscaping",
	.Commuting    = "Commuting",
	.Disputes     = "Disputes",
}

Effect :: enum u8 {
	To_Hit, // ships' computers (combat, step 6)
	Survey, // fewer bad readings
	Armour, // ships' armour (step 6)
	Factory_Cost, // factories cost less
	Shield, // ships' shields (step 6)
	Base_Defence, // defence bases fight harder (step 6)
	Settle, // a hostile planet type can be settled
	Households, // every colony holds this many percent more
	Less_Waste, // factories make less waste
	Speed, // ships go further each turn
	Fuel, // ships can stay away longer
	Weapon, // ships' weapons (step 6)
}

Tech :: struct {
	name:   string,
	effect: Effect,
	amount: int,
	planet: Planet_Type, // for Settle
}

TECHS_PER_FIELD :: 8
OFFERED_PER_FIELD :: 5
UPGRADE_FEE :: 5 // BJ per ship per upgrade
SURVEY_STEP :: 5 // percent fewer bad readings per Survey tech
RESEARCH_SLIDERS := [Field]int {
	.Spreadsheets = 17,
	.Renovation   = 17,
	.Fences       = 16,
	.Landscaping  = 17,
	.Commuting    = 17,
	.Disputes     = 16,
}

// The cost of the tech at a level (1 to 8) in research points.
tech_cost :: proc(level: int) -> int {
	return 10 * level * level
}

TECHS := [Field][TECHS_PER_FIELD]Tech {
	.Spreadsheets = {
		{name = "Pivot Tables", effect = .To_Hit, amount = 1},
		{name = "Conditional Formatting", effect = .Survey, amount = 1},
		{name = "Macros", effect = .To_Hit, amount = 1},
		{name = "VLOOKUP", effect = .Survey, amount = 1},
		{name = "Shared Drive", effect = .To_Hit, amount = 1},
		{name = "Version History", effect = .Survey, amount = 1},
		{name = "Data Validation", effect = .To_Hit, amount = 1},
		{name = "Cloud Sync", effect = .To_Hit, amount = 2},
	},
	.Renovation = {
		{name = "Flat-Pack Furniture", effect = .Factory_Cost, amount = 1},
		{name = "Load-Bearing Walls", effect = .Armour, amount = 1},
		{name = "Power Tools", effect = .Factory_Cost, amount = 1},
		{name = "Drywall", effect = .Armour, amount = 1},
		{name = "Building Permits", effect = .Factory_Cost, amount = 1},
		{name = "Steel Joists", effect = .Armour, amount = 1},
		{name = "Open-Plan Living", effect = .Factory_Cost, amount = 1},
		{name = "Reinforced Concrete", effect = .Armour, amount = 2},
	},
	.Fences = {
		{name = "Picket Fence", effect = .Shield, amount = 1},
		{name = "Garden Gate", effect = .Base_Defence, amount = 1},
		{name = "Chain Link", effect = .Shield, amount = 1},
		{name = "Privacy Hedge", effect = .Base_Defence, amount = 1},
		{name = "Electric Fence", effect = .Shield, amount = 1},
		{name = "Gated Community", effect = .Base_Defence, amount = 1},
		{name = "Laser Grid", effect = .Shield, amount = 1},
		{name = "Force Field", effect = .Shield, amount = 2},
	},
	.Landscaping = {
		{name = "Topsoil", effect = .Settle, planet = .Barren},
		{name = "Raised Beds", effect = .Households, amount = 10},
		{name = "Composting", effect = .Less_Waste, amount = 1},
		{name = "Drought Plants", effect = .Settle, planet = .Dead},
		{name = "Rock Garden", effect = .Settle, planet = .Inferno},
		{name = "Water Feature", effect = .Settle, planet = .Toxic},
		{name = "Lead-Lined Gnomes", effect = .Settle, planet = .Radiated},
		{name = "Greenhouse", effect = .Households, amount = 10},
	},
	.Commuting = {
		{name = "Carpool Lane", effect = .Speed, amount = 1},
		{name = "Bigger Tank", effect = .Fuel, amount = 1},
		{name = "Cruise Control", effect = .Speed, amount = 1},
		{name = "Roof Box", effect = .Fuel, amount = 1},
		{name = "Satnav", effect = .Speed, amount = 1},
		{name = "Spare Jerry Can", effect = .Fuel, amount = 1},
		{name = "Express Lane", effect = .Speed, amount = 1},
		{name = "Long-Range Tank", effect = .Fuel, amount = 2},
	},
	.Disputes = {
		{name = "Strongly Worded Letter", effect = .Weapon, amount = 1},
		{name = "Petition", effect = .Weapon, amount = 1},
		{name = "Cease and Desist", effect = .Weapon, amount = 1},
		{name = "Small Claims Court", effect = .Weapon, amount = 1},
		{name = "Injunction", effect = .Weapon, amount = 1},
		{name = "Restraining Order", effect = .Weapon, amount = 1},
		{name = "Class Action", effect = .Weapon, amount = 1},
		{name = "Eviction Notice", effect = .Weapon, amount = 2},
	},
}

Research :: struct {
	offered: [Field][TECHS_PER_FIELD]bool,
	known:   [Field][TECHS_PER_FIELD]bool,
	stored:  [Field]int, // points put towards the field's next tech
	slider:  [Field]int, // percent of research each field gets; sums to 100
	locked:  [Field]bool,
}

// Picks the five techs of each field on offer this game.
offer_techs :: proc(res: ^Research, r: ^Rng) {
	for f in Field {
		res.offered[f] = {}
		for placed := 0; placed < OFFERED_PER_FIELD; {
			i := rng_int(r, TECHS_PER_FIELD)
			if !res.offered[f][i] {
				res.offered[f][i] = true
				placed += 1
			}
		}
	}
	res.slider = RESEARCH_SLIDERS
}

// The field's next tech: the cheapest one on offer not yet known, or -1 when it has nothing left.
next_tech :: proc(res: ^Research, f: Field) -> int {
	for i in 0 ..< TECHS_PER_FIELD {
		if res.offered[f][i] && !res.known[f][i] {
			return i
		}
	}
	return -1
}

known_count :: proc(res: ^Research, f: Field) -> int {
	n := 0
	for k in res.known[f] {
		if k {
			n += 1
		}
	}
	return n
}

// The sum of a kind of effect over every tech an empire knows.
bonus :: proc(g: ^Game, owner: int, e: Effect) -> int {
	n := 0
	for f in Field {
		for i in 0 ..< TECHS_PER_FIELD {
			if g.empires[owner].tech.known[f][i] && TECHS[f][i].effect == e {
				n += TECHS[f][i].amount
			}
		}
	}
	return n
}

// Whether an empire's Moving Vans can settle a type: Tardigrades anything, others by Landscaping.
can_settle :: proc(g: ^Game, owner: int, planet: Planet_Type) -> bool {
	return g.empires[owner].race == .Tardigrades || can_settle_by_tech(g, owner, planet)
}

can_settle_by_tech :: proc(g: ^Game, owner: int, planet: Planet_Type) -> bool {
	if TYPE_PERCENT[planet] > 0 {
		return true
	}
	for f in Field {
		for i in 0 ..< TECHS_PER_FIELD {
			t := TECHS[f][i]
			if g.empires[owner].tech.known[f][i] && t.effect == .Settle && t.planet == planet {
				return true
			}
		}
	}
	return false
}

set_research_slider :: proc(res: ^Research, f: Field, value: int) {
	set_share(slice.enumerated_array(&res.slider), slice.enumerated_array(&res.locked), int(f), value)
}

// Shares out an empire's research this turn and finishes whatever techs it pays for.
research_turn :: proc(g: ^Game, owner: int) {
	e := &g.empires[owner]
	res := &e.tech
	pool := e.research
	e.research = 0
	given := 0
	for f in Field {
		share := pool * res.slider[f] / 100
		res.stored[f] += share
		given += share
	}
	// Rounding leftovers go to the first field still working.
	for f in Field {
		if next_tech(res, f) >= 0 {
			res.stored[f] += pool - given
			break
		}
	}
	for f in Field {
		for {
			i := next_tech(res, f)
			if i < 0 || res.stored[f] < tech_cost(i + 1) {
				break
			}
			res.stored[f] -= tech_cost(i + 1)
			learn(g, owner, f, i)
		}
	}
}

// A tech is learned: say so (if it is yers), and bill the upgrades it brings to ships.
learn :: proc(g: ^Game, owner: int, f: Field, i: int) {
	before := empire_kit(g, owner)
	g.empires[owner].tech.known[f][i] = true
	t := TECHS[f][i]
	b: Text
	add(&b, "Book Club finishes ")
	add(&b, t.name)
	add(&b, " (")
	add(&b, FIELD_NAMES[f])
	add(&b, "): ")
	add(&b, describe_effect(t))
	add(&b, ".")
	tell(g, owner, text(&b))
	bill_upgrades(g, owner, before)
}

// What a tech does, in a few words.
describe_effect :: proc(t: Tech) -> string {
	@(static) b: Text
	b = {}
	switch t.effect {
	case .To_Hit:
		add(&b, "ships aim better")
	case .Survey:
		add(&b, "fewer bad survey readings")
	case .Armour:
		add(&b, "ships take more hits")
	case .Factory_Cost:
		add(&b, "factories cost less")
	case .Shield:
		add(&b, "ships' shields")
	case .Base_Defence:
		add(&b, "stronger defence bases")
	case .Settle:
		add(&b, PLANET_NAMES[t.planet])
		add(&b, " worlds can be settled")
	case .Households:
		add(&b, "more room on every colony")
	case .Less_Waste:
		add(&b, "factories make less waste")
	case .Speed:
		add(&b, "ships go faster")
	case .Fuel:
		add(&b, "ships go further")
	case .Weapon:
		add(&b, "ships hit harder")
	}
	return text(&b)
}
