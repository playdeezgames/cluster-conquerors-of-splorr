#+build !js
package game

import "core:strings"
import "core:testing"

@(test)
test_the_clubhouse :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for seed in u64(1) ..= 100 {
		init_game(g, seed)
		c := g.clubhouse
		s := g.stars[c]
		testing.expect(t, !is_home(g, c) && !s.wormhole)
		testing.expect_value(t, s.name, "The Clubhouse")
		testing.expect(t, s.planet == .Garden && s.size == .Large && s.special == .Artifacts)
		testing.expect(t, g.moth_alive)
	}
}

@(test)
test_the_moth_eats_small_fleets :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	rival_fleet(g, g.clubhouse, PLAYER, only(.Golf_Cart, 2))
	find_battles(g)
	testing.expect_value(t, g.mode, Mode.Battle)
	testing.expect_value(t, g.battle.owners[1], MOTH)
	command(g, .South)
	command(g, .Confirm) // fight it out
	testing.expect(t, g.moth_alive)
	testing.expect(t, fleet_at(g, g.clubhouse) == nil)
}

@(test)
test_a_big_fleet_sees_off_the_moth_and_the_clubhouse_pays :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	rival_fleet(g, g.clubhouse, PLAYER, only(.Monster_Truck, 8))
	bt := setup_battle(g, g.clubhouse, PLAYER, MOTH)
	fight_it_out(g, &bt)
	finish_battle(g, &bt)
	testing.expect(t, !g.moth_alive)
	known := 0
	for f in Field {
		known += known_count(&g.empires[PLAYER].tech, f)
	}
	g.empires[PLAYER].bj = 10000 // so the upgrades the lost techs bring are paid
	van := new_fleet(g)
	van.ships = only(.Moving_Van, 1)
	arrive(g, van, g.clubhouse)
	testing.expect(t, colony_at(g, g.clubhouse) != nil)
	after := 0
	for f in Field {
		after += known_count(&g.empires[PLAYER].tech, f)
	}
	testing.expect_value(t, after, known + LOST_TECHS)
}

@(test)
test_nobody_settles_under_the_moth :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	van := new_fleet(g)
	van.ships = only(.Moving_Van, 1)
	arrive(g, van, g.clubhouse)
	testing.expect(t, any_colony(g, g.clubhouse) == nil)
	// And the rivals neither explore nor settle there while it lives.
	for e in 1 ..< g.empire_count {
		g.stars[g.clubhouse].reports[e] = {filed = true, planet = .Garden, size = .Large}
		testing.expect(t, best_settle_target(g, e, g.empires[e].home, nil) != g.clubhouse)
	}
}

// Everyone has met everyone.
all_met :: proc(g: ^Game) {
	for a in 0 ..< g.empire_count {
		for b in 0 ..< g.empire_count {
			g.empires[a].met[b] = a != b
		}
	}
}

// Whether the minutes say something, reading the wrapped lines as one text.
minutes_contain :: proc(g: ^Game, s: string) -> bool {
	all := strings.builder_make(context.temp_allocator)
	for i in 0 ..< g.council.lines {
		strings.write_string(&all, strings.trim_space(message(&g.council.minutes[i])))
		strings.write_byte(&all, ' ')
	}
	return strings.contains(strings.to_string(all), s)
}

@(test)
test_no_meetings_until_everyone_has_met :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	council_turn(g)
	testing.expect(t, !g.council.started)
	all_met(g)
	council_turn(g)
	testing.expect(t, g.council.started)
	testing.expect_value(t, g.council.meetings, 1)
	testing.expect_value(t, g.mode, Mode.Council)
	testing.expect(t, g.council.voting) // the first meeting votes
	testing.expect_value(t, g.council.next, g.turn + COUNCIL_EVERY)
}

@(test)
test_complaints_and_fines :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	all_met(g)
	g.empires[PLAYER].bj = 1000
	colony_at(g, g.home).waste = MESS_WASTE
	council_turn(g)
	testing.expect(t, minutes_contain(g, "are a mess"))
	testing.expect_value(t, g.empires[PLAYER].bj, 950)
	// Parked at someone else's colony, and fees unpaid: one complaint at a time.
	g2 := new(Game)
	defer free(g2)
	init_game(g2, SEED)
	all_met(g2)
	g2.empires[PLAYER].bj = 1000
	rival_fleet(g2, g2.empires[1].home, PLAYER, only(.Golf_Cart, 1))
	council_turn(g2)
	testing.expect(t, minutes_contain(g2, "not theirs"))
	testing.expect_value(t, g2.empires[PLAYER].bj, 950)
}

@(test)
test_captured_colonies_complain_every_meeting :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	h := landing(g, 20)
	land_troops(g)
	testing.expect(t, colony_at(g, h) != nil)
	all_met(g)
	g.empires[PLAYER].bj = 1000
	council_turn(g)
	testing.expect(t, minutes_contain(g, "speak to the manager"))
	testing.expect(t, g.empires[PLAYER].bj < 1000)
}

@(test)
test_rivals_never_vote_for_you :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	all_met(g)
	council_turn(g)
	for _ in 0 ..< 200 {
		for e in 1 ..< g.empire_count {
			v := rival_vote(g, e)
			if v != .Abstain {
				testing.expect(t, g.council.candidates[int(v) - 1] != PLAYER)
			}
		}
	}
}

@(test)
test_elected_with_two_thirds_and_the_duty :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	all_met(g)
	colony_at(g, g.home).households = 1000 // far more than everyone else put together
	council_turn(g)
	testing.expect_value(t, g.council.candidates[0], PLAYER)
	// The bylaw vote comes first (abstain: the third row); then vote for yerselves by keys, the first row.
	testing.expect(t, g.council.bylaw_voting)
	command(g, .South)
	command(g, .South)
	command(g, .Confirm)
	testing.expect(t, !g.council.bylaw_voting)
	testing.expect_value(t, g.council.choice, 0)
	command(g, .Confirm)
	testing.expect_value(t, g.council.president, PLAYER)
	testing.expect(t, g.council.ever_won)
	testing.expect(t, minutes_contain(g, "Yer the President"))
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Map)
	// Play goes on; the next meeting costs the President.
	g.empires[PLAYER].bj = 100
	g.turn = g.council.next
	council_turn(g)
	testing.expect(t, minutes_contain(g, "biscuits"))
	testing.expect(t, g.empires[PLAYER].bj <= 100 - PRESIDENT_DUTY)
	testing.expect_value(t, g.outcome, Outcome.Playing)
}

@(test)
test_without_two_thirds_nobody_is_elected :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	all_met(g)
	council_turn(g)
	// Everyone starts the same size: nobody can reach two thirds alone.
	pointer(g, COLONY_X + 4, vote_row_y(2) + 3, .Touch) // abstain on the bylaw, by a tap
	pointer(g, COLONY_X + 4, vote_row_y(2) + 3, .Touch) // and for President
	testing.expect_value(t, g.council.president, NO_OWNER)
	testing.expect(t, minutes_contain(g, "Nobody has two thirds"))
	pointer(g, COLONY_X + 4, 20, .Touch)
	testing.expect_value(t, g.mode, Mode.Map)
}

@(test)
test_a_meeting_waits_for_yer_battles :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	all_met(g)
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Golf_Cart, 1))
	rival_fleet(g, to, PLAYER, only(.Pickup, 3))
	find_battles(g)
	testing.expect_value(t, g.mode, Mode.Battle)
	council_turn(g)
	testing.expect_value(t, g.mode, Mode.Battle)
	testing.expect(t, g.council.waiting)
	command(g, .South)
	command(g, .Confirm) // fight it out
	testing.expect_value(t, g.mode, Mode.Council)
}
