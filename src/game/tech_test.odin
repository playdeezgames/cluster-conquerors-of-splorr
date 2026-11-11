#+build !js
package game

import "core:testing"

// Marks the tech with this name known (offered or not), as if just researched, bills and all.
learn_named :: proc(g: ^Game, name: string) {
	for f in Field {
		for i in 0 ..< TECHS_PER_FIELD {
			if TECHS[f][i].name == name {
				g.empires[PLAYER].tech.offered[f][i] = true
				learn(g, PLAYER, f, i)
				return
			}
		}
	}
	panic("no such tech")
}

@(test)
test_five_of_eight_on_offer :: proc(t: ^testing.T) {
	a := new(Game)
	defer free(a)
	b := new(Game)
	defer free(b)
	init_game(a, SEED)
	init_game(b, SEED)
	testing.expect(t, a.empires[PLAYER].tech.offered == b.empires[PLAYER].tech.offered)
	for f in Field {
		n := 0
		for o in a.empires[PLAYER].tech.offered[f] {
			if o {
				n += 1
			}
		}
		testing.expect_value(t, n, OFFERED_PER_FIELD)
	}
	differs := false
	for seed in u64(1) ..= 20 {
		init_game(b, seed)
		if b.empires[PLAYER].tech.offered != a.empires[PLAYER].tech.offered {
			differs = true
		}
	}
	testing.expect(t, differs)
	sum := 0
	for v in a.empires[PLAYER].tech.slider {
		sum += v
	}
	testing.expect_value(t, sum, 100)
}

@(test)
test_research_buys_the_cheapest_offered :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	res := &g.empires[PLAYER].tech
	for f in Field {
		res.slider[f] = 0
	}
	res.slider[.Disputes] = 100
	first := next_tech(res, .Disputes)
	testing.expect(t, first >= 0)
	g.empires[PLAYER].research = tech_cost(first + 1) - 1
	research_turn(g, PLAYER)
	testing.expect(t, !res.known[.Disputes][first])
	g.empires[PLAYER].research = 1
	research_turn(g, PLAYER)
	testing.expect(t, res.known[.Disputes][first])
	testing.expect_value(t, res.stored[.Disputes], 0)
	testing.expect(t, next_tech(res, .Disputes) != first)
	// A field with nothing left keeps nothing back from the others.
	for i in 0 ..< TECHS_PER_FIELD {
		res.known[.Disputes][i] = res.offered[.Disputes][i]
	}
	testing.expect_value(t, next_tech(res, .Disputes), -1)
}

@(test)
test_book_club_feeds_research :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	end_turn(g)
	stored := 0
	for v in g.empires[PLAYER].tech.stored {
		stored += v
	}
	learned := 0
	for f in Field {
		learned += known_count(&g.empires[PLAYER].tech, f)
	}
	testing.expect(t, stored > 0 || learned > 0)
	testing.expect_value(t, g.empires[PLAYER].research, 0)
}

@(test)
test_landscaping_opens_hostile_worlds :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	testing.expect(t, !can_settle(g, PLAYER, .Toxic))
	testing.expect_value(t, planet_max(g, PLAYER, .Toxic, .Large), 0)
	learn_named(g, "Water Feature")
	testing.expect(t, can_settle(g, PLAYER, .Toxic))
	testing.expect_value(t, planet_max(g, PLAYER, .Toxic, .Large), 30)
	to := van_target(g, .Toxic)
	send_fleet(g, PLAYER, g.home, to, only(.Moving_Van, 1))
	for _ in 0 ..< 4 {
		end_turn(g)
	}
	testing.expect(t, colony_at(g, to) != nil)
}

@(test)
test_households_factories_and_waste :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	testing.expect_value(t, colony_max(g, g.home), 70)
	learn_named(g, "Raised Beds")
	testing.expect_value(t, colony_max(g, g.home), 77)
	testing.expect_value(t, factory_cost(g, PLAYER), 10)
	learn_named(g, "Flat-Pack Furniture")
	learn_named(g, "Power Tools")
	testing.expect_value(t, factory_cost(g, PLAYER), 8)
	c := colony_at(g, g.home)
	c.factories = 40
	testing.expect_value(t, waste_made(g, c), 10)
	learn_named(g, "Composting")
	testing.expect_value(t, waste_made(g, c), 5)
}

@(test)
test_spreadsheets_cut_bad_readings :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	learn_named(g, "Conditional Formatting")
	learn_named(g, "VLOOKUP")
	learn_named(g, "Version History")
	for k in 0 ..< 2000 {
		i := k % g.star_count
		if i == g.home {
			continue
		}
		survey(g, PLAYER, i)
		s := g.stars[i]
		testing.expect(t, s.reports[PLAYER].planet == s.planet && s.reports[PLAYER].size == s.size)
	}
}

@(test)
test_upgrades_are_billed_per_ship :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	home := fleet_at(g, g.home)
	ships := fleet_size(home) // 6: 2 Inspectors, a Moving Van, a Gas Can, 2 Golf Carts
	g.empires[PLAYER].bj = 100
	learn_named(g, "Carpool Lane") // speed: every ship
	testing.expect_value(t, g.empires[PLAYER].bj, 100 - ships * UPGRADE_FEE)
	testing.expect_value(t, home.kit[.Speed], 1)
	testing.expect_value(t, fleet_speed(home), 4)
	testing.expect_value(t, owed(g, home), 0)
	learn_named(g, "Petition") // weapons: only the two Golf Carts
	testing.expect_value(t, g.empires[PLAYER].bj, 100 - ships * UPGRADE_FEE - 2 * UPGRADE_FEE)
	testing.expect_value(t, home.kit[.Weapon], 1)
}

@(test)
test_unpaid_ships_keep_old_kit_until_paid :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	home := fleet_at(g, g.home)
	g.empires[PLAYER].bj = 0
	learn_named(g, "Bigger Tank")
	testing.expect_value(t, home.kit[.Fuel], 0)
	testing.expect_value(t, fleet_fuel(home), 4)
	testing.expect_value(t, owed(g, home), fleet_size(home) * UPGRADE_FEE)
	testing.expect(t, !pay_upgrades(g, home))
	g.empires[PLAYER].bj = 1000
	testing.expect(t, pay_upgrades(g, home))
	testing.expect_value(t, fleet_fuel(home), 5)
	testing.expect_value(t, g.empires[PLAYER].bj, 1000 - fleet_size(home) * UPGRADE_FEE)
	testing.expect_value(t, owed(g, home), 0)
	// A new ship is built with the new kit, and one sent off takes the kit along.
	send_fleet(g, PLAYER, g.home, nearest_other(g), only(.Inspector, 1))
	for &f in g.fleets {
		if f.used && f.owner == PLAYER {
			testing.expect_value(t, f.kit[.Fuel], 1)
		}
	}
}

@(test)
test_joined_fleet_goes_with_the_oldest_kit :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	old := new_fleet(g)
	old.ships = only(.Golf_Cart, 1)
	old.star = NO_STAR
	g.empires[PLAYER].bj = 1000
	learn_named(g, "Satnav")
	// The fleet in transit was up to date too, so it was upgraded with the rest.
	testing.expect_value(t, old.kit[.Speed], 1)
	old.kit[.Speed] = 0
	dock(g, old, g.home)
	testing.expect_value(t, fleet_at(g, g.home).kit[.Speed], 0)
	testing.expect(t, owed(g, fleet_at(g, g.home)) > 0)
}

@(test)
test_research_screen_by_keys_and_pointer :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	command(g, .Research)
	testing.expect_value(t, g.mode, Mode.Research)
	res := &g.empires[PLAYER].tech
	command(g, .East) // Spreadsheets 17 -> 20
	testing.expect_value(t, res.slider[.Spreadsheets], 20)
	command(g, .Confirm)
	testing.expect(t, res.locked[.Spreadsheets])
	command(g, .South)
	bar_x := COLONY_X + BAR_COL * GLYPH_W
	pointer(g, bar_x + BAR_CELLS * GLYPH_W / 2, research_row_y(int(Field.Disputes)) + 3, .Mouse)
	testing.expect_value(t, res.slider[.Disputes], 50)
	testing.expect_value(t, res.slider[.Spreadsheets], 20)
	sum := 0
	for v in res.slider {
		sum += v
	}
	testing.expect_value(t, sum, 100)
	command(g, .Research)
	testing.expect_value(t, g.mode, Mode.Map)
	// The panel's link opens it too.
	pointer(g, PANEL_TEXT_X + 4, RESEARCH_LINK_Y + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Research)
	pointer(g, COLONY_X + 4, research_row_y(RESEARCH_BACK_ROW) + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Map)
}

@(test)
test_pay_row_in_the_ship_list :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	g.empires[PLAYER].bj = 0
	learn_named(g, "Roof Box")
	g.empires[PLAYER].bj = 500
	open_fleet(g, g.home)
	_, n := fleet_rows(g)
	for _ in 0 ..< n {
		command(g, .South)
	}
	testing.expect_value(t, g.row, n)
	command(g, .Confirm)
	testing.expect_value(t, owed(g, fleet_at(g, g.home)), 0)
	testing.expect_value(t, g.mode, Mode.Fleet)
}

@(test)
test_tech_names_fit :: proc(t: ^testing.T) {
	for f in Field {
		testing.expect(t, text_width(FIELD_NAMES[f]) <= (BAR_COL - 1) * GLYPH_W)
		for tech in TECHS[f] {
			// "Next: <name>  ddd/ddd" on the second line of the row.
			testing.expect(t, (2 + 6 + len(tech.name) + 9) * GLYPH_W <= VIEW_W * TILE - COLONY_X)
		}
	}
}
