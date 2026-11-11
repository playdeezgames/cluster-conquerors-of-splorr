#+build !js
package game

import "core:testing"

@(test)
test_carpools_take_households :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	c.build = .Carpool
	c.stored[.Parking] = SHIPS[.Carpool].cost * 2 - 1 // two this turn with what Parking adds
	before := c.households
	run_colony(g, g.home)
	testing.expect_value(t, fleet_at(g, g.home).ships[.Carpool], 2)
	testing.expect(t, c.households <= before - 2 * CARPOOL_LOAD + 3) // less what grew back this turn
	// A colony too small to spare them waits.
	c.households = 2 // still no more than a Carpool's load after this turn's growth
	c.stored[.Parking] = 100
	run_colony(g, g.home)
	testing.expect_value(t, fleet_at(g, g.home).ships[.Carpool], 2)
}

// Yer Carpools parked at a rival's home with its defences gone.
landing :: proc(g: ^Game, carpools: int) -> int {
	h := g.empires[1].home
	if f := fleet_of(g, h, 1); f != nil {
		f^ = {}
	}
	colony_of(g, h, 1).bases = 0
	rival_fleet(g, h, PLAYER, only(.Carpool, carpools))
	return h
}

@(test)
test_a_big_landing_takes_the_colony :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := landing(g, 20) // 100 troops against 25 militia
	rival_race := g.empires[1].race
	land_troops(g)
	c := colony_at(g, h)
	testing.expect(t, c != nil)
	testing.expect_value(t, c.race, rival_race)
	testing.expect_value(t, c.captured, 1)
	testing.expect(t, c.households > 0 && c.households < HOME_HOUSEHOLDS)
	testing.expect_value(t, c.factories, HOME_FACTORIES)
	testing.expect(t, c.slider == NEW_SLIDERS)
	testing.expect(t, g.stars[h].reports[PLAYER].filed)
	testing.expect(t, fleet_at(g, h) == nil) // the Carpools are used up
	testing.expect(t, refuels_at(g, h, PLAYER))
}

@(test)
test_a_small_landing_is_seen_off :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := landing(g, 1) // 5 troops against 25 militia
	land_troops(g)
	c := colony_of(g, h, 1)
	testing.expect(t, c != nil)
	testing.expect(t, c.households < HOME_HOUSEHOLDS)
	testing.expect(t, fleet_at(g, h) == nil)
}

@(test)
test_no_landing_past_bases_or_ships :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := landing(g, 20)
	colony_of(g, h, 1).bases = 1
	land_troops(g)
	testing.expect(t, colony_of(g, h, 1) != nil)
	testing.expect_value(t, fleet_at(g, h).ships[.Carpool], 20)
	colony_of(g, h, 1).bases = 0
	rival_fleet(g, h, 1, only(.Inspector, 1)) // even an Inspector in orbit stops a landing
	land_troops(g)
	testing.expect(t, colony_of(g, h, 1) != nil)
}

@(test)
test_captured_people_keep_their_trait_then_assimilate :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	g.empires[1].race = .Rabbits
	colony_of(g, g.empires[1].home, 1).race = .Rabbits
	h := landing(g, 20)
	land_troops(g)
	c := colony_at(g, h)
	testing.expect_value(t, c.race, Race.Rabbits)
	for _ in 0 ..< ASSIMILATE_TURNS {
		assimilate(g)
	}
	testing.expect_value(t, c.race, g.empires[PLAYER].race)
	testing.expect_value(t, c.captured, 0)
}

@(test)
test_conquest_and_defeat :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	// Take every rival colony away (by hand) and the game is won.
	for i in 0 ..< g.star_count {
		if c := any_colony(g, i); c != nil && c.owner != PLAYER {
			c^ = {}
		}
	}
	check_conquest(g)
	testing.expect(t, g.empires[1].out && g.empires[2].out)
	for &f in g.fleets {
		testing.expect(t, !f.used || f.owner == PLAYER)
	}
	testing.expect_value(t, g.outcome, Outcome.Won)
	testing.expect_value(t, g.mode, Mode.Game_Over)
	// Enter/OK starts a new cluster on the species screen.
	seed := g.seed
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Choose_Race)
	testing.expect_value(t, g.seed, seed + 1)
	testing.expect_value(t, g.outcome, Outcome.Playing)
	// Lose yer last colony and it is over.
	colony_at(g, g.home)^ = {}
	end_turn(g)
	testing.expect_value(t, g.outcome, Outcome.Lost)
	testing.expect_value(t, g.mode, Mode.Game_Over)
}

@(test)
test_rivals_invade_what_they_saw_undefended :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := g.empires[1].home
	// The rival saw one of yer colonies with nothing to defend it, near enough for Carpools.
	target := NO_STAR
	for i in 0 ..< g.star_count {
		if i != h && !g.stars[i].wormhole && any_colony(g, i) == nil {
			target = i
			break
		}
	}
	// Bring it within a Carpool's reach (a hand-made layout, whatever the seed).
	g.stars[target].x = clamp(g.stars[h].x + 6, 0, GALAXY_W - 1)
	g.stars[target].y = g.stars[h].y
	found_colony(g, target, 10)
	update_sight(g)
	g.empires[1].intel[target] = {
		seen       = true,
		owner      = PLAYER,
		households = 10,
	}
	prey, need := invasion_target(g, 1, h)
	testing.expect_value(t, prey, target)
	testing.expect_value(t, need, 2) // 5 militia, half as many again: 7 troops, two Carpools
	fleet_of(g, h, 1).ships[.Carpool] = need
	ai_invade(g, 1, prey, need)
	going := false
	for &f in g.fleets {
		if f.used && f.owner == 1 && f.star == NO_STAR && f.to == target && f.ships[.Carpool] == need {
			going = true
		}
	}
	testing.expect(t, going)
}
