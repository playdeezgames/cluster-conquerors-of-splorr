#+build !js
package game

import "core:strings"
import "core:testing"

@(test)
test_three_homes_far_apart :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 200 {
		init_game(g, seed)
		testing.expect_value(t, g.empire_count, 3)
		for e in 0 ..< g.empire_count {
			h := g.empires[e].home
			s := g.stars[h]
			testing.expect(t, !s.wormhole)
			testing.expect_value(t, s.planet, Planet_Type.Terran)
			c := colony_of(g, h, e)
			testing.expect(t, c != nil && c.households == HOME_HOUSEHOLDS)
			testing.expect(t, fleet_of(g, h, e) != nil)
			testing.expect(t, s.reports[e].filed)
			for o in 0 ..< e {
				oh := g.stars[g.empires[o].home]
				dx, dy := oh.x - s.x, oh.y - s.y
				testing.expectf(t, dx * dx + dy * dy >= 15 * 15, "seed %v: homes %v and %v too close", seed, o, e)
			}
		}
		// Nobody knows anybody at the start; the rivals' homes are out of yer sight.
		for e in 1 ..< g.empire_count {
			testing.expect(t, !g.empires[PLAYER].met[e])
			testing.expect(t, !g.stars[g.empires[e].home].reports[PLAYER].filed)
		}
	}
}

@(test)
test_choosing_a_species :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for r in Race {
		init_game(g, SEED)
		start_choosing(g)
		testing.expect_value(t, g.mode, Mode.Choose_Race)
		for _ in 0 ..< int(r) {
			command(g, .South)
		}
		command(g, .Confirm)
		testing.expect_value(t, g.mode, Mode.Map)
		testing.expect_value(t, g.empires[PLAYER].race, r)
		testing.expect_value(t, colony_at(g, g.home).race, r)
		a, b := g.empires[1].race, g.empires[2].race
		testing.expect(t, a != r && b != r && a != b)
	}
	// By pointer: a tap picks a row, a second tap chooses.
	init_game(g, SEED)
	start_choosing(g)
	pointer(g, COLONY_X + 4, race_row_y(2) + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Choose_Race)
	pointer(g, COLONY_X + 4, race_row_y(2) + 3, .Touch)
	testing.expect_value(t, g.empires[PLAYER].race, Race.Rabbits)
}

@(test)
test_species_traits :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	// The trait follows the colony's people.
	c := colony_at(g, g.home)
	plain_p := production(g, g.home)
	plain_r := research_points(g, g.home)
	c.race = .Beavers
	testing.expect_value(t, production(g, g.home), 25 + 45) // 30 worked factories make 45
	c.race = .Owls
	testing.expect_value(t, production(g, g.home), plain_p)
	testing.expect_value(t, research_points(g, g.home), plain_r * 3 / 2)
	// Rabbits grow faster from the same start.
	c.race = .Geese
	c.households = 20
	run_colony(g, g.home)
	geese := c.households
	c.race = .Rabbits
	c.households = 20
	run_colony(g, g.home)
	testing.expect(t, c.households > geese)
}

@(test)
test_fleets_of_different_empires_do_not_join :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	rival := new_fleet(g, 1)
	rival.ships = only(.Golf_Cart, 1)
	dock(g, rival, g.home)
	testing.expect(t, fleet_of(g, g.home, 1) != nil)
	testing.expect_value(t, fleet_at(g, g.home).ships[.Golf_Cart], START_SHIPS[.Golf_Cart])
	testing.expect(t, !refuels_at(g, g.home, 1))
}

// The rivals play by the rules: over many turns they survey, settle and build, never break the
// sliders, and nothing they do shows in yer news unless you see it.
@(test)
test_rivals_expand_honestly :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	settled_somewhere, surveyed_total := 0, 0
	for seed in u64(1) ..= 20 {
		init_game(g, seed)
		for _ in 0 ..< 60 {
			end_turn(g)
			for &m in g.news {
				msg := message(&m)
				testing.expect(t, !strings.contains(msg, "Survey filed"))
				testing.expect(t, !strings.contains(msg, "movers"))
			}
			for e in 1 ..< g.empire_count {
				for i in 0 ..< g.star_count {
					if c := colony_of(g, i, e); c != nil {
						sum := 0
						for v in c.slider {
							sum += v
						}
						testing.expect_value(t, sum, 100)
					}
				}
			}
		}
		for e in 1 ..< g.empire_count {
			colonies, surveyed := 0, 0
			for i in 0 ..< g.star_count {
				if colony_of(g, i, e) != nil {
					colonies += 1
				}
				if g.stars[i].reports[e].filed {
					surveyed += 1
				}
			}
			// Fuel keeps Inspectors near home and old reports get misfiled, so few are on file at once.
			testing.expectf(t, surveyed >= 1, "seed %v empire %v surveyed %v", seed, e, surveyed)
			surveyed_total += surveyed
			if colonies > 1 {
				settled_somewhere += 1
			}
		}
	}
	testing.expectf(t, settled_somewhere >= 24, "rivals settled a second world in %v of 40 games", settled_somewhere)
	testing.expectf(t, surveyed_total >= 3 * 40, "rivals held %v reports over 40 games", surveyed_total)
}

@(test)
test_first_contact :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	// Park a rival Inspector next to yer home.
	f := new_fleet(g, 1)
	f.ships = only(.Inspector, 1)
	dock(g, f, g.home)
	update_sight(g)
	testing.expect(t, g.empires[PLAYER].met[1])
	testing.expect(t, g.empires[1].met[PLAYER])
	found := false
	for &m in g.news {
		if strings.contains(message(&m), "First contact") || strings.contains(message(&m), "They hate you") {
			found = true
		}
	}
	testing.expect(t, found)
}

@(test)
test_a_threatened_rival_builds_warships :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.empires[1].home
	f := new_fleet(g, PLAYER)
	f.ships = only(.Golf_Cart, 3)
	dock(g, f, h)
	update_sight(g)
	ai_turn(g, 1)
	c := colony_of(g, h, 1)
	testing.expect_value(t, c.build, Ship_Type.Pickup)
	testing.expect(t, c.slider[.Parking] >= 30)
}
