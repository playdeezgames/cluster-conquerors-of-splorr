#+build !js
package game

import "core:strings"
import "core:testing"

@(test)
test_grudges_start_where_they_should :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU)
	testing.expect_value(t, g.empires[2].grudge[PLAYER], GRUDGE_AT_YOU)
	testing.expect_value(t, g.empires[1].grudge[1], 0)
	// Dogs are hated less, by everyone.
	init_game(g, SEED)
	choose_race(g, .Dogs)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - DOG_GRUDGE_OFF)
	for seed in u64(1) ..= 40 {
		init_game(g, seed)
		choose_race(g, .Owls)
		for e in 1 ..< g.empire_count {
			other := 3 - e
			want := g.empires[other].race == .Dogs ? GRUDGE_AT_RIVAL - DOG_GRUDGE_OFF : GRUDGE_AT_RIVAL
			testing.expect_value(t, g.empires[e].grudge[other], want)
		}
	}
}

@(test)
test_grudges_grow_and_cool :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	// A battle: both sides.
	to := nearest_other(g)
	rival_fleet(g, to, 1, only(.Golf_Cart, 1))
	rival_fleet(g, to, PLAYER, only(.Pickup, 4))
	bt := setup_battle(g, to, PLAYER, 1)
	fight_it_out(g, &bt)
	finish_battle(g, &bt)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU + GRUDGE_BATTLE)
	testing.expect_value(t, g.empires[PLAYER].grudge[1], GRUDGE_AT_RIVAL + GRUDGE_BATTLE)
	testing.expect_value(t, g.empires[2].grudge[PLAYER], GRUDGE_AT_YOU)
	// Cooling, a point a turn, never below the start.
	grudge_turn(g)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU + GRUDGE_BATTLE - 1)
	for _ in 0 ..< 30 {
		grudge_turn(g)
	}
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU)
	// Never over the top.
	add_grudge(g, 1, PLAYER, 500)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_MAX)
}

@(test)
test_landings_and_complaints_make_grudges :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	landing(g, 20)
	land_troops(g)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU + GRUDGE_CAPTURE)
	init_game(g, SEED)
	choose_race(g, .Owls)
	landing(g, 1)
	land_troops(g)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU + GRUDGE_LANDING)
	// A fine at a meeting: everyone else minds.
	init_game(g, SEED)
	choose_race(g, .Owls)
	mine, theirs := g.empires[PLAYER].grudge[1], g.empires[2].grudge[1]
	fine(g, 1, "test.")
	testing.expect_value(t, g.empires[PLAYER].grudge[1], mine + GRUDGE_COMPLAINT)
	testing.expect_value(t, g.empires[2].grudge[1], theirs + GRUDGE_COMPLAINT)
}

// You hear about a rival's grudge only as gossip, when its band changes, and only once you have met.
@(test)
test_grudge_gossip :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	add_grudge(g, 1, PLAYER, 25)
	grudge_turn(g)
	testing.expect(t, !news_has(g, "bins")) // not met yet
	init_game(g, SEED)
	choose_race(g, .Owls)
	g.empires[PLAYER].met[1] = true
	add_grudge(g, 1, PLAYER, 25)
	grudge_turn(g)
	testing.expect(t, news_has(g, "written yer name on their bins"))
	g.news = {}
	grudge_turn(g) // 84: still the same band, nothing said
	testing.expect(t, !news_has(g, "bins"))
}

news_has :: proc(g: ^Game, s: string) -> bool {
	for &m in g.news {
		if strings.contains(message(&m), s) {
			return true
		}
	}
	return false
}

// A rival sends its warships after whoever it hates most, among what it could beat.
@(test)
test_rivals_attack_whom_they_hate_most :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	for hate_two in ([]bool{true, false}) {
		init_game(g, SEED)
		choose_race(g, .Owls)
		h := g.empires[1].home
		fleet_of(g, h, 1).ships[.Pickup] = 6
		fleet_of(g, h, 1).kit[.Fuel] = 10
		targets: [2]int = {NO_STAR, NO_STAR}
		n := 0
		for i in 0 ..< g.star_count {
			if n < 2 && i != h && i != g.clubhouse && !g.stars[i].wormhole && send_problem(g, 1, h, i, only(.Pickup, 6)) == "" {
				targets[n] = i
				n += 1
			}
		}
		if !testing.expect_value(t, n, 2) {
			return
		}
		g.empires[1].intel[targets[0]] = {seen = true, owner = PLAYER, strength = 4}
		g.empires[1].intel[targets[1]] = {seen = true, owner = 2, strength = 4}
		g.empires[1].grudge[2] = hate_two ? 90 : 10
		ai_attack(g, 1)
		want := hate_two ? targets[1] : targets[0]
		going := false
		for &f in g.fleets {
			if f.used && f.owner == 1 && f.star == NO_STAR && f.ships[.Pickup] > 0 {
				going = f.to == want
			}
		}
		testing.expect(t, going)
	}
}
