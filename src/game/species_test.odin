#+build !js
package game

import "core:testing"

// Slice 2 step 0: all ten species on the screen, by keys and taps, and the rivals drawn from all ten.
@(test)
test_all_ten_species_can_be_chosen :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for r in Race {
		init_game(g, SEED)
		start_choosing(g)
		for _ in 0 ..< int(r) {
			command(g, .South)
		}
		command(g, .Confirm)
		testing.expect_value(t, g.empires[PLAYER].race, r)
	}
	// Left and Right change column: the Beavers' neighbour is the Ants.
	init_game(g, SEED)
	start_choosing(g)
	command(g, .East)
	testing.expect_value(t, Race(g.row), Race.Ants)
	command(g, .West)
	testing.expect_value(t, Race(g.row), Race.Beavers)
	// A tap in the second column picks, a second tap chooses.
	x, y := race_col_x(int(Race.Badgers)), race_row_y(int(Race.Badgers))
	pointer(g, x + 4, y + 2, .Touch)
	testing.expect_value(t, g.mode, Mode.Choose_Race)
	testing.expect_value(t, Race(g.row), Race.Badgers)
	pointer(g, x + 4, y + 2, .Touch)
	testing.expect_value(t, g.empires[PLAYER].race, Race.Badgers)
	testing.expect_value(t, colony_at(g, g.home).race, Race.Badgers)
}

@(test)
test_rivals_come_from_all_ten :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	seen: [Race]bool
	for seed in u64(1) ..= 60 {
		init_game(g, seed)
		choose_race(g, .Owls)
		a, b := g.empires[1].race, g.empires[2].race
		testing.expect(t, a != .Owls && b != .Owls && a != b)
		seen[a] = true
		seen[b] = true
	}
	for r in Race {
		testing.expect_value(t, seen[r], r != .Owls)
	}
}

// Every factory a colony's households can work makes a point (two per household; three for Ants).
@(test)
test_factories_worked_and_ants :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	c.households = 20
	c.factories = 60
	testing.expect_value(t, factory_cap(c), 40)
	testing.expect_value(t, production(g, g.home), 10 + 40)
	c.race = .Ants
	testing.expect_value(t, factory_cap(c), 60)
	testing.expect_value(t, production(g, g.home), 10 + 60)
	// Ants keep building past where others stop.
	c.factories = 40
	c.stored[.Home_Improvement] = FACTORY_COST * 5
	run_colony(g, g.home)
	testing.expect(t, c.factories > 40)
}

@(test)
test_tardigrades_live_on_any_rock_and_grow_slowly :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	testing.expect(t, !can_settle(g, PLAYER, .Toxic))
	g.empires[PLAYER].race = .Tardigrades
	testing.expect(t, can_settle(g, PLAYER, .Toxic))
	testing.expect_value(t, planet_max(g, PLAYER, .Toxic, .Large), 30)
	// A Tardigrade colony keeps its room under an owner who could not settle there.
	to := nearest_other(g)
	s := &g.stars[to]
	s.planet, s.size = .Radiated, .Medium
	c := found_colony(g, to, 2)
	g.empires[PLAYER].race = .Geese
	testing.expect(t, colony_max(g, to) > 1)
	c.race = .Geese
	testing.expect_value(t, colony_max(g, to), 1)
	// Half the growth of the same colony's Geese.
	h := colony_at(g, g.home)
	h.race = .Geese
	h.households = 20
	run_colony(g, g.home)
	geese := h.households - 20
	h.race = .Tardigrades
	h.households = 20
	run_colony(g, g.home)
	testing.expect_value(t, h.households - 20, max(1, geese / 2))
}

@(test)
test_tortoises_are_hit_less :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Golf_Cart, 1))
	rival_fleet(g, to, PLAYER, only(.Golf_Cart, 1))
	g.empires[1].race = .Tortoises
	bt := setup_battle(g, to, PLAYER, 1)
	mine, theirs := &bt.stacks[0], &bt.stacks[1]
	testing.expect_value(t, mine.side, 0)
	testing.expect_value(t, aim_at(g, &bt, mine, theirs), mine.to_hit * TORTOISE_HIT_PERCENT / 100)
	testing.expect_value(t, aim_at(g, &bt, theirs, mine), theirs.to_hit)
}

@(test)
test_badgers_on_the_ground :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.empires[1].home
	c := colony_of(g, h, 1)
	c.race = .Geese
	g.empires[PLAYER].race = .Geese
	testing.expect_value(t, landing_odds(g, PLAYER, c), 50)
	g.empires[PLAYER].race = .Badgers
	testing.expect_value(t, landing_odds(g, PLAYER, c), 65)
	c.race = .Badgers
	testing.expect_value(t, landing_odds(g, PLAYER, c), 50)
	g.empires[PLAYER].race = .Geese
	testing.expect_value(t, landing_odds(g, PLAYER, c), 35)
}
