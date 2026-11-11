#+build !js
package game

import "core:testing"

slider_sum :: proc(c: ^Colony) -> int {
	n := 0
	for v in c.slider {
		n += v
	}
	return n
}

@(test)
test_sliders_always_add_up :: proc(t: ^testing.T) {
	c: Colony
	c.slider = HOME_SLIDERS
	r := Rng{99}
	for _ in 0 ..< 5000 {
		ch := Chore(rng_int(&r, len(Chore)))
		if rng_int(&r, 10) == 0 {
			c.locked[ch] = !c.locked[ch]
			continue
		}
		before := c
		set_slider(&c, ch, rng_int(&r, 101))
		testing.expect_value(t, slider_sum(&c), 100)
		for v, o in c.slider {
			testing.expect(t, v >= 0)
			if before.locked[o] {
				testing.expect_value(t, v, before.slider[o])
			}
		}
	}
}

@(test)
test_slider_shares_in_proportion :: proc(t: ^testing.T) {
	c: Colony
	c.slider = {
		.Parking          = 20,
		.Fencing          = 0,
		.Home_Improvement = 40,
		.Lawn_Care        = 20,
		.Book_Club        = 20,
	}
	c.locked[.Book_Club] = true
	set_slider(&c, .Parking, 50)
	testing.expect_value(t, c.slider[.Parking], 50)
	testing.expect_value(t, c.slider[.Book_Club], 20)
	testing.expect_value(t, c.slider[.Home_Improvement], 20) // 30 shared 2:1 with Lawn Care
	testing.expect_value(t, c.slider[.Lawn_Care], 10)
	testing.expect_value(t, c.slider[.Fencing], 0)
	// Nothing can push past the locked share.
	set_slider(&c, .Parking, 100)
	testing.expect_value(t, c.slider[.Parking], 80)
	// A locked slider does not move when set.
	set_slider(&c, .Book_Club, 0)
	testing.expect_value(t, c.slider[.Book_Club], 20)
}

@(test)
test_home_starts_settled :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	testing.expect(t, c != nil)
	testing.expect_value(t, c.households, HOME_HOUSEHOLDS)
	testing.expect_value(t, colony_max(g, g.home), 70)
	testing.expect_value(t, c.factories, HOME_FACTORIES)
	testing.expect_value(t, production(g, g.home), 55) // 25 from households, 30 from factories
	testing.expect_value(t, tax(g, g.home), 5)
	testing.expect_value(t, chore_points(g, g.home, .Home_Improvement), 25) // half of the 50 after tax
	testing.expect(t, refuels_at(g, g.home, PLAYER))
}

@(test)
test_a_turn_of_the_home_colony :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	run_colony(g, g.home)
	testing.expect_value(t, g.empires[PLAYER].bj, 5)
	testing.expect_value(t, g.empires[PLAYER].research, 10)
	testing.expect_value(t, c.factories, HOME_FACTORIES + 2) // 25 points: two factories, 5 put by
	testing.expect_value(t, c.stored[.Home_Improvement], 5)
	testing.expect(t, c.households > HOME_HOUSEHOLDS)
	testing.expect_value(t, c.waste, 0) // 7 waste, 5 points of Lawn Care clean 10
}

@(test)
test_parking_builds_ships :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	c.build = .Golf_Cart
	before := fleet_at(g, g.home).ships[.Golf_Cart]
	// 10 points a turn of Parking: a Golf Cart (20) every two turns.
	for _ in 0 ..< 4 {
		run_colony(g, g.home)
	}
	testing.expect_value(t, fleet_at(g, g.home).ships[.Golf_Cart], before + 2)
}

@(test)
test_factories_stop_at_what_households_can_work :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	c.households, c.wear = 10, 60 // room for 10
	c.factories = 19
	c.stored[.Home_Improvement] = 5 // with this turn's 7, one more factory
	run_colony(g, g.home)
	testing.expect_value(t, c.factories, 20)
	bj := g.empires[PLAYER].bj
	run_colony(g, g.home)
	testing.expect_value(t, c.factories, 20)
	testing.expect(t, g.empires[PLAYER].bj > bj + tax(g, g.home)) // the surplus went to BJ
}

@(test)
test_waste_wears_the_planet_down :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	c.factories = 100
	c.households = 70
	set_slider(c, .Lawn_Care, 0)
	max_before := colony_max(g, g.home)
	for _ in 0 ..< 10 {
		run_colony(g, g.home)
	}
	testing.expect(t, colony_max(g, g.home) < max_before)
	// Enough Lawn Care keeps it tidy.
	c.waste = 0
	set_slider(c, .Lawn_Care, 60)
	max_now := colony_max(g, g.home)
	for _ in 0 ..< 10 {
		run_colony(g, g.home)
	}
	testing.expect_value(t, colony_max(g, g.home), max_now)
}

@(test)
test_rich_and_artifacts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	plain := production(g, g.home)
	rp := research_points(g, g.home)
	g.stars[g.home].special = .Rich
	testing.expect_value(t, production(g, g.home), plain * 3 / 2)
	g.stars[g.home].special = .Poor
	testing.expect_value(t, production(g, g.home), plain / 2)
	g.stars[g.home].special = .Artifacts
	testing.expect_value(t, research_points(g, g.home), rp * 2)
}

// A star in reach of home for the Moving Van, with its planet set as wanted.
van_target :: proc(g: ^Game, planet: Planet_Type) -> int {
	to := NO_STAR
	for i in 0 ..< g.star_count {
		if i != g.home && !g.stars[i].wormhole && send_problem(g, PLAYER, g.home, i, only(.Moving_Van, 1)) == "" {
			to = i
			break
		}
	}
	if to != NO_STAR {
		g.stars[to].planet, g.stars[to].size, g.stars[to].special = planet, .Medium, .None
	}
	return to
}

@(test)
test_moving_van_settles_and_sees_the_truth :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 20 {
		init_game(g, seed)
		to := van_target(g, .Ocean)
		if to == NO_STAR {
			continue
		}
		// The Inspector got it wrong.
		g.stars[to].reports[PLAYER] = {
			filed   = true,
			planet  = .Garden,
			size    = .Large,
			special = .Rich,
		}
		send_fleet(g, PLAYER, g.home, to, only(.Moving_Van, 1))
		for _ in 0 ..< 8 {
			end_turn(g)
		}
		c := colony_at(g, to)
		testing.expect(t, c != nil)
		testing.expect_value(t, g.stars[to].reports[PLAYER].planet, Planet_Type.Ocean)
		testing.expect_value(t, g.stars[to].reports[PLAYER].size, Planet_Size.Medium)
		testing.expect_value(t, colony_max(g, to), 63)
		// The listing said Rich; after a few turns the colony knows better.
		testing.expect_value(t, g.stars[to].reports[PLAYER].special, Special.None)
		testing.expect(t, fleet_at(g, to) == nil) // the van was used up
		testing.expect(t, refuels_at(g, to, PLAYER))
	}
}

@(test)
test_moving_van_will_not_settle_hostile :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := van_target(g, .Toxic)
	testing.expect(t, to != NO_STAR)
	send_fleet(g, PLAYER, g.home, to, only(.Moving_Van, 1))
	for _ in 0 ..< 4 {
		end_turn(g)
	}
	testing.expect(t, colony_at(g, to) == nil)
	f := fleet_at(g, to)
	testing.expect(t, f != nil && f.ships[.Moving_Van] == 1)
	testing.expect_value(t, g.stars[to].reports[PLAYER].planet, Planet_Type.Toxic)
}

@(test)
test_colony_screen_by_keys :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Colony)
	c := colony_at(g, g.home)
	command(g, .East) // Parking 20 -> 25
	testing.expect_value(t, c.slider[.Parking], 25)
	testing.expect_value(t, slider_sum(c), 100)
	command(g, .Confirm) // lock it
	testing.expect(t, c.locked[.Parking])
	command(g, .East)
	testing.expect_value(t, c.slider[.Parking], 25)
	for _ in 0 ..< BUILD_ROW {
		command(g, .South)
	}
	command(g, .East)
	testing.expect_value(t, c.build, Ship_Type.Moving_Van)
	command(g, .West)
	command(g, .West)
	testing.expect_value(t, c.build, Ship_Type.Monster_Truck)
	command(g, .End_Turn)
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect_value(t, g.turn, 2)
}

@(test)
test_colony_screen_by_pointer :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	open_colony(g, g.home)
	c := colony_at(g, g.home)
	bar_x := COLONY_X + BAR_COL * GLYPH_W
	// The middle of the Book Club bar sets it to 50.
	pointer(g, bar_x + BAR_CELLS * GLYPH_W / 2, colony_row_y(int(Chore.Book_Club)) + 3, .Mouse)
	testing.expect_value(t, c.slider[.Book_Club], 50)
	testing.expect_value(t, slider_sum(c), 100)
	pointer(g, COLONY_X + LOCK_COL * GLYPH_W + 2, colony_row_y(int(Chore.Book_Club)) + 3, .Mouse)
	testing.expect(t, c.locked[.Book_Club])
	pointer(g, COLONY_X + BUILD_RIGHT_COL * GLYPH_W + 2, colony_row_y(BUILD_ROW) + 3, .Mouse)
	testing.expect_value(t, c.build, Ship_Type.Moving_Van)
	pointer(g, COLONY_X + 4, colony_row_y(COLONY_BACK_ROW) + 3, .Mouse)
	testing.expect_value(t, g.mode, Mode.Map)
}

@(test)
test_colony_effects_fit :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	for ch in Chore {
		testing.expect(t, EFFECT_COL * GLYPH_W + text_width(chore_effect(g, g.home, ch)) <= VIEW_W * TILE - COLONY_X)
		testing.expect(t, text_width(CHORE_NAMES[ch]) <= (BAR_COL - 1) * GLYPH_W)
	}
	for s in SHIPS {
		testing.expect(t, BUILD_LEFT_COL + 2 + len(s.name) < BUILD_RIGHT_COL)
	}
}
