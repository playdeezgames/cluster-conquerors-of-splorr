#+build !js
package game

import "core:testing"

// A game with one other star at a known trip from home, for checking travel and fuel.
nearest_other :: proc(g: ^Game) -> int {
	best, best_d := NO_STAR, max(int)
	h := g.stars[g.home]
	for i in 0 ..< g.star_count {
		s := g.stars[i]
		d := (s.x - h.x) * (s.x - h.x) + (s.y - h.y) * (s.y - h.y)
		if i != g.home && !s.wormhole && d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

only :: proc(t: Ship_Type, n: int) -> (ships: [Ship_Type]int) {
	ships[t] = n
	return
}

@(test)
test_starting_fleet :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	f := fleet_at(g, g.home)
	testing.expect(t, f != nil)
	testing.expect(t, f.ships == START_SHIPS)
	testing.expect_value(t, f.refills, GAS_CAN_REFILLS)
	testing.expect_value(t, fleet_fuel(f), 4) // Moving Van and Golf Carts hold 4
	testing.expect_value(t, fleet_speed(f), 3) // the Moving Van and the Gas Can are slowest
}

@(test)
test_trip_turns_round_up :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	g.star_count = 2
	g.stars[0] = {x = 0, y = 0}
	g.stars[1] = {x = 8, y = 6} // 10 cells
	testing.expect_value(t, trip_turns(g, 0, 1, 4), 3)
	testing.expect_value(t, trip_turns(g, 0, 1, 5), 2)
	testing.expect_value(t, trip_turns(g, 0, 1, 10), 1)
	testing.expect_value(t, trip_turns(g, 0, 1, 2), 5)
}

@(test)
test_send_travel_and_survey :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	to := nearest_other(g)
	ships := only(.Inspector, 1)
	testing.expect_value(t, send_problem(g, PLAYER, g.home, to, ships), "")
	turns := trip_turns(g, g.home, to, SHIPS[.Inspector].speed)
	send_fleet(g, PLAYER, g.home, to, ships)
	testing.expect_value(t, fleet_at(g, g.home).ships[.Inspector], 1)
	for _ in 0 ..< turns - 1 {
		end_turn(g)
		testing.expect(t, fleet_at(g, to) == nil)
	}
	end_turn(g)
	f := fleet_at(g, to)
	testing.expect(t, f != nil)
	testing.expect_value(t, f.ships[.Inspector], 1)
	testing.expect_value(t, f.away, turns)
	testing.expect(t, g.stars[to].reports[PLAYER].filed)
}

@(test)
test_out_of_range_refused :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	g.star_count = 3
	g.stars[0] = {x = 0, y = 0}
	g.stars[1] = {x = 0, y = 13} // 13 cells: a Moving Van (3 a turn, 4 turns of fuel) needs 5 turns
	g.stars[2] = {x = 0, y = 12} // 12 cells: 4 turns, just enough
	g.home = 0
	f := new_fleet(g)
	f.star = 0
	f.ships = only(.Moving_Van, 1)
	testing.expect_value(t, send_problem(g, PLAYER, 0, 1, only(.Moving_Van, 1)), "Out of range.")
	testing.expect_value(t, send_problem(g, PLAYER, 0, 2, only(.Moving_Van, 1)), "")
	testing.expect_value(t, send_problem(g, PLAYER, 0, 2, only(.Moving_Van, 0)), "Nobody is going.")
	testing.expect_value(t, send_problem(g, PLAYER, 0, 0, only(.Moving_Van, 1)), "They are already here.")
}

@(test)
test_stranded_until_a_gas_can_comes :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	g.rng = Rng{1}
	g.star_count = 2
	g.stars[0] = {x = 0, y = 0}
	g.stars[1] = {x = 0, y = 8} // 8 cells: Golf Carts (4 a turn) take 2 turns, Gas Cans (3 a turn) 3
	g.home = 0
	g.stars[0].planet, g.stars[0].size = .Terran, .Medium
	found_colony(g, 0, 10)
	home := new_fleet(g)
	home.star = 0
	home.ships = only(.Golf_Cart, 1)
	home.ships[.Gas_Can] = 1
	home.refills = GAS_CAN_REFILLS
	send_fleet(g, PLAYER, 0, 1, only(.Golf_Cart, 1))
	for _ in 0 ..< 3 {
		end_turn(g)
	}
	cart := fleet_at(g, 1)
	testing.expect(t, cart != nil)
	testing.expect(t, !stranded(g, cart)) // 2 turns there and 1 sitting: one turn of fuel left
	testing.expect_value(t, fleet_range(cart), 1)
	end_turn(g)
	cart = fleet_at(g, 1)
	testing.expect(t, stranded(g, cart))
	testing.expect_value(t, send_problem(g, PLAYER, 1, 0, only(.Golf_Cart, 1)), "Out of range.")
	for _ in 0 ..< 10 {
		end_turn(g)
	}
	testing.expect(t, stranded(g, fleet_at(g, 1))) // it waits, forever if need be
	send_fleet(g, PLAYER, 0, 1, only(.Gas_Can, 1))
	testing.expect_value(t, fleet_at(g, 0), (^Fleet)(nil))
	for _ in 0 ..< 3 {
		end_turn(g)
	}
	joined := fleet_at(g, 1)
	testing.expect_value(t, joined.ships[.Golf_Cart], 1)
	testing.expect_value(t, joined.ships[.Gas_Can], 1)
	testing.expect(t, !stranded(g, joined))
	testing.expect_value(t, joined.away, 0)
	testing.expect_value(t, joined.refills, GAS_CAN_REFILLS - 1)
	// Home again: the tanks and the Gas Can fill up.
	send_fleet(g, PLAYER, 1, 0, joined.ships)
	for _ in 0 ..< 3 {
		end_turn(g)
	}
	back := fleet_at(g, 0)
	testing.expect_value(t, back.away, 0)
	testing.expect_value(t, back.refills, GAS_CAN_REFILLS)
}

@(test)
test_wormhole_throws_and_is_known :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 50 {
		init_game(g, seed)
		hole := NO_STAR
		for i in 0 ..< g.star_count {
			if g.stars[i].wormhole {
				hole = i
				break
			}
		}
		g.stars[g.home].colony.slider[.Home_Improvement] += g.stars[g.home].colony.slider[.Parking]
		g.stars[g.home].colony.slider[.Parking] = 0 // no new ships this turn
		f := new_fleet(g)
		f.ships = only(.Inspector, 1)
		f.from, f.to, f.left, f.total = g.home, hole, 1, 1
		end_turn(g)
		testing.expect(t, g.stars[hole].wormhole_known[PLAYER])
		testing.expect(t, fleet_at(g, hole) == nil)
		// The thrown Inspector came out at a star that is not a wormhole (perhaps home, joining the fleet there).
		inspectors := 0
		for &o in g.fleets {
			if o.used && o.owner == PLAYER {
				testing.expect(t, o.star != NO_STAR && !g.stars[o.star].wormhole)
				inspectors += o.ships[.Inspector]
			}
		}
		testing.expect_value(t, inspectors, START_SHIPS[.Inspector] + 1)
	}
}

// Over many surveys the lies turn up at about the planned rates, and the truth is never touched.
@(test)
test_survey_lie_rates :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	bad, fake, plain, flattering_only := 0, 0, 0, true
	N :: 4000
	for k in 0 ..< N {
		i := k % g.star_count
		if i == g.home {
			continue
		}
		s := &g.stars[i]
		truth := s^
		survey(g, PLAYER, i)
		testing.expect(t, s.planet == truth.planet && s.size == truth.size && s.special == truth.special)
		r := s.reports[PLAYER]
		if r.planet != s.planet || r.size != s.size {
			bad += 1
		}
		if s.special == .None {
			plain += 1
			if r.special != .None {
				fake += 1
				flattering_only = flattering_only && (r.special == .Rich || r.special == .Artifacts)
			}
		}
	}
	surveys := N - N / g.star_count
	testing.expectf(t, bad * 100 > surveys * 12 && bad * 100 < surveys * 18, "bad readings %v of %v", bad, surveys)
	testing.expectf(t, fake * 6 > plain * 8 / 10 && fake * 6 < plain * 12 / 10, "fake specials %v of %v", fake, plain)
	testing.expect(t, flattering_only)
}

@(test)
test_reports_get_misfiled_but_home_does_not :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	for i in 0 ..< g.star_count {
		survey(g, PLAYER, i)
	}
	g.stars[g.home].reports[PLAYER] = {filed = true, planet = .Terran, size = .Medium}
	for _ in 0 ..< 300 {
		end_turn(g)
	}
	lost := 0
	for i in 0 ..< g.star_count {
		if !g.stars[i].reports[PLAYER].filed {
			lost += 1
		}
	}
	testing.expect(t, lost > 0)
	testing.expect(t, g.stars[g.home].reports[PLAYER].filed)
}

// The whole order by keys: open the ships at home, send one Inspector, choose a star, send.
@(test)
test_orders_by_keys :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Colony)
	// Down to "Ships parked here" and in.
	for _ in 0 ..< SHIPS_ROW {
		command(g, .South)
	}
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Fleet)
	rows, n := fleet_rows(g)
	testing.expect_value(t, n, 4)
	testing.expect_value(t, rows[0], Ship_Type.Inspector)
	// Leave one Inspector going, nobody else.
	command(g, .West)
	for _ in 1 ..< n {
		command(g, .South)
		for _ in 0 ..< 5 {
			command(g, .West)
		}
	}
	testing.expect(t, g.send == only(.Inspector, 1))
	command(g, .End_Turn)
	testing.expect_value(t, g.turn, 1)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Destination)
	// Find a direction that leads to a star in range.
	sent := false
	for c in Command.North ..= Command.South_East {
		command(g, c)
		if g.cursor != g.home && send_problem(g, PLAYER, g.home, g.cursor, g.send) == "" {
			command(g, .Confirm)
			sent = true
			break
		}
		g.cursor = g.home
	}
	testing.expect(t, sent)
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect_value(t, g.cursor, g.home)
	testing.expect_value(t, fleet_at(g, g.home).ships[.Inspector], 1)
	moving := 0
	for &o in g.fleets {
		if o.used && o.star == NO_STAR {
			moving += 1
		}
	}
	testing.expect_value(t, moving, 1)
}

// The same by pointer: tap home twice, tap a count, Choose where, tap a star twice.
@(test)
test_orders_by_pointer :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.stars[g.home]
	hx, hy := cell_px(g, h.x, h.y)
	pointer(g, hx + 5, hy + 5, .Touch)
	testing.expect_value(t, g.mode, Mode.Colony)
	pointer(g, COLONY_X + 4, colony_row_y(SHIPS_ROW) + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Fleet)
	// The Inspector row's "<" takes one off.
	pointer(g, PANEL_TEXT_X + COUNT_COL * GLYPH_W + 2, FLEET_TOP + 3, .Touch)
	testing.expect_value(t, g.send[.Inspector], 1)
	pointer(g, PANEL_TEXT_X + (COUNT_COL + 2) * GLYPH_W + 2, FLEET_TOP + 3, .Touch)
	testing.expect_value(t, g.send[.Inspector], 2)
	pointer(g, PANEL_TEXT_X + 4, ACTION_Y + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Destination)
	pointer(g, PANEL_TEXT_X + 4, BACK_Y + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Fleet)
	pointer(g, PANEL_TEXT_X + 4, BACK_Y + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Map)
	// On a star with ships and no colony, the second tap opens the ships straight away.
	g.mode = .Map
}

@(test)
test_describe_report_articles :: proc(t: ^testing.T) {
	b: Text
	r := Report {
		filed   = true,
		planet  = .Ocean,
		size    = .Large,
		special = .Artifacts,
	}
	describe_report(&b, &r)
	testing.expect_value(t, text(&b), "an Ancient Artifacts, Large Ocean world.")
	b = {}
	r.special = .None
	describe_report(&b, &r)
	testing.expect_value(t, text(&b), "a Large Ocean world.")
}
