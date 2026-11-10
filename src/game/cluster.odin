package game

import "core:slice"

// The cluster: stars placed from the game's seed, each with one planet (as in Master of Orion), and a
// few wormholes that look exactly like unsurveyed stars. Slice 1 has one size, "small".

GALAXY_W :: 60 // map cells
GALAXY_H :: 40
EDGE :: 2 // no star within this many cells of the map's edge
MIN_SPACING :: 5 // cells between any two stars, at least
STAR_COUNT :: 20 // stars in a small cluster, wormholes included
WORMHOLES :: STAR_COUNT / 8 // one in eight
MAX_STARS :: 32

NO_STAR :: -1

Planet_Type :: enum u8 {
	Garden,
	Terran,
	Ocean,
	Jungle,
	Arid,
	Steppe,
	Desert,
	Tundra,
	Barren,
	Dead,
	Inferno,
	Toxic,
	Radiated,
}

PLANET_NAMES := [Planet_Type]string {
	.Garden   = "Garden",
	.Terran   = "Terran",
	.Ocean    = "Ocean",
	.Jungle   = "Jungle",
	.Arid     = "Arid",
	.Steppe   = "Steppe",
	.Desert   = "Desert",
	.Tundra   = "Tundra",
	.Barren   = "Barren",
	.Dead     = "Dead",
	.Inferno  = "Inferno",
	.Toxic    = "Toxic",
	.Radiated = "Radiated",
}

// How often each type turns up; the good ones are rare.
PLANET_WEIGHTS := [Planet_Type]int {
	.Garden   = 2,
	.Terran   = 5,
	.Ocean    = 6,
	.Jungle   = 6,
	.Arid     = 7,
	.Steppe   = 7,
	.Desert   = 8,
	.Tundra   = 8,
	.Barren   = 10,
	.Dead     = 10,
	.Inferno  = 8,
	.Toxic    = 8,
	.Radiated = 8,
}

// The palette colour a planet of each type is drawn in.
PLANET_COLORS := [Planet_Type]u8 {
	.Garden   = COLOR_LIME,
	.Terran   = COLOR_GREEN,
	.Ocean    = COLOR_BLUE,
	.Jungle   = COLOR_GREEN,
	.Arid     = COLOR_ORANGE,
	.Steppe   = COLOR_YELLOW,
	.Desert   = COLOR_YELLOW,
	.Tundra   = COLOR_LIGHT,
	.Barren   = COLOR_MID,
	.Dead     = COLOR_DARK,
	.Inferno  = COLOR_RED,
	.Toxic    = COLOR_PURPLE,
	.Radiated = COLOR_CYAN,
}

Planet_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

SIZE_NAMES := [Planet_Size]string {
	.Small  = "Small",
	.Medium = "Medium",
	.Large  = "Large",
}

Special :: enum u8 {
	None,
	Rich,
	Poor,
	Artifacts,
}

SPECIAL_NAMES := [Special]string {
	.None      = "",
	.Rich      = "Rich",
	.Poor      = "Poor",
	.Artifacts = "Ancient Artifacts",
}

SPECIAL_WEIGHTS := [Special]int {
	.None      = 14,
	.Rich      = 3,
	.Poor      = 3,
	.Artifacts = 1,
}

Star :: struct {
	x, y:     int,
	name:     string, // the star's straight name; the HOA's paperwork uses the lot number (index + 1)
	wormhole: bool, // looks exactly like an unsurveyed star
	planet:   Planet_Type,
	size:     Planet_Size,
	special:  Special,
	report:   Report, // what yer Inspectors filed about it (may be wrong, may be lost)
	wormhole_known: bool, // something has been through it
	colony:   Colony, // yers, if colony.owned
}

// Straight star names, drawn without repeats for each cluster.
STAR_NAMES := [?]string {
	"Vega Minor", "Kepler's Rest", "Altair", "Deneb Gate", "Procyon", "Mira", "Castor", "Pollux",
	"Rigel Far", "Achernar", "Hadar", "Acrux", "Spica", "Antares Low", "Fomalhaut", "Mimosa",
	"Regulus", "Adhara", "Shaula", "Bellatrix", "Elnath", "Alnilam", "Alnair", "Alioth",
	"Dubhe", "Mirfak", "Wezen", "Sargas", "Kaus", "Avior", "Alkaid", "Menkar",
	"Atria", "Alhena", "Peacock", "Polaris Two", "Mirzam", "Alphard", "Hamal", "Diphda",
	"Nunki", "Menkent", "Saiph", "Tiaki", "Ankaa", "Merak", "Enif", "Izar",
	"Sabik", "Scheat", "Markab", "Phecda", "Aludra", "Gienah", "Zosma", "Arneb",
	"Muhlifain", "Kochab", "Rasalhague", "Algol", "Naos", "Alderamin", "Denebola", "Tarazed",
}

// Fills g.stars from the seed: places STAR_COUNT stars at least MIN_SPACING apart, numbers them in
// reading order (so Lot 1 is top left), names them, gives each a planet, hides WORMHOLES wormholes
// among them, and picks a home star away from the edges with a Terran world.
make_cluster :: proc(g: ^Game, seed: u64) {
	r := Rng{seed}
	for {
		if place_stars(g, &r) {
			break
		}
	}
	// Reading order: by row, then column.
	for i in 1 ..< g.star_count {
		for j := i; j > 0; j -= 1 {
			a, b := g.stars[j - 1], g.stars[j]
			if a.y < b.y || (a.y == b.y && a.x <= b.x) {
				break
			}
			g.stars[j - 1], g.stars[j] = b, a
		}
	}
	// Names: a shuffled draw from the list.
	order: [len(STAR_NAMES)]int
	for i in 0 ..< len(order) {
		order[i] = i
	}
	for i := len(order) - 1; i > 0; i -= 1 {
		j := rng_int(&r, i + 1)
		order[i], order[j] = order[j], order[i]
	}
	for i in 0 ..< g.star_count {
		s := &g.stars[i]
		s.name = STAR_NAMES[order[i]]
		s.planet = Planet_Type(rng_weighted(&r, slice.enumerated_array(&PLANET_WEIGHTS)))
		s.size = Planet_Size(rng_int(&r, 3))
		s.special = Special(rng_weighted(&r, slice.enumerated_array(&SPECIAL_WEIGHTS)))
	}
	// Home: a star at least 8 cells from every edge, so it has neighbours all round.
	candidates: [MAX_STARS]int
	n := 0
	for i in 0 ..< g.star_count {
		s := g.stars[i]
		if s.x >= 8 && s.y >= 8 && s.x < GALAXY_W - 8 && s.y < GALAXY_H - 8 {
			candidates[n] = i
			n += 1
		}
	}
	g.home = n > 0 ? candidates[rng_int(&r, n)] : rng_int(&r, g.star_count)
	home := &g.stars[g.home]
	home.planet, home.size, home.special = .Terran, .Medium, .None
	home.report = {
		filed   = true,
		planet  = home.planet,
		size    = home.size,
		special = home.special,
	}
	// Wormholes: any stars but home.
	for placed := 0; placed < WORMHOLES; {
		i := rng_int(&r, g.star_count)
		if i != g.home && !g.stars[i].wormhole {
			g.stars[i].wormhole = true
			placed += 1
		}
	}
}

// One attempt at placing every star by throwing darts; false if it ran out of tries.
place_stars :: proc(g: ^Game, r: ^Rng) -> bool {
	g.star_count = 0
	for _ in 0 ..< 5000 {
		x := rng_range(r, EDGE, GALAXY_W - 1 - EDGE)
		y := rng_range(r, EDGE, GALAXY_H - 1 - EDGE)
		ok := true
		for i in 0 ..< g.star_count {
			dx, dy := g.stars[i].x - x, g.stars[i].y - y
			if dx * dx + dy * dy < MIN_SPACING * MIN_SPACING {
				ok = false
				break
			}
		}
		if ok {
			g.stars[g.star_count] = Star {
				x = x,
				y = y,
			}
			g.star_count += 1
			if g.star_count == STAR_COUNT {
				return true
			}
		}
	}
	return false
}

// The star at a cell, or NO_STAR.
star_at :: proc(g: ^Game, x, y: int) -> int {
	for i in 0 ..< g.star_count {
		if g.stars[i].x == x && g.stars[i].y == y {
			return i
		}
	}
	return NO_STAR
}

// The star nearest a cell within `reach` cells (Chebyshev), or NO_STAR. For clicks and taps, which
// need not land exactly on the star.
star_near :: proc(g: ^Game, x, y, reach: int) -> int {
	best, best_d := NO_STAR, max(int)
	for i in 0 ..< g.star_count {
		dx, dy := g.stars[i].x - x, g.stars[i].y - y
		if abs(dx) > reach || abs(dy) > reach {
			continue
		}
		d := dx * dx + dy * dy
		if d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

// The star to move to from star `from` in direction (dx, dy): the closest star roughly that way.
// Stars within 67.5 degrees of the direction are preferred, weighted against straying sideways; if
// there are none, any star on that side will do. NO_STAR if there is nothing that way.
star_toward :: proc(g: ^Game, from: int, dx, dy: int) -> int {
	f := g.stars[from]
	best, best_score := NO_STAR, max(int)
	fallback, fallback_score := NO_STAR, max(int)
	// Work in integers: the direction scaled so diagonals and straights compare fairly (x10 for straights,
	// x7 for diagonals, about 10/sqrt(2)).
	scale := dx != 0 && dy != 0 ? 7 : 10
	ux, uy := dx * scale, dy * scale
	for i in 0 ..< g.star_count {
		if i == from {
			continue
		}
		vx, vy := g.stars[i].x - f.x, g.stars[i].y - f.y
		along := vx * ux + vy * uy // distance along the direction, x10
		if along <= 0 {
			continue
		}
		across := abs(vx * uy - vy * ux) // distance sideways, x10
		score := along + 2 * across
		// Within 67.5 degrees: tan(67.5) is about 2.414, so across < 2.414 * along.
		if across * 1000 < along * 2414 {
			if score < best_score {
				best, best_score = i, score
			}
		} else if score < fallback_score {
			fallback, fallback_score = i, score
		}
	}
	return best != NO_STAR ? best : fallback
}
