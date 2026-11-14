#+build !js
package game

import "core:testing"

// A colony of yers that is not yer home, for events that skip homes.
second_colony :: proc(g: ^Game) -> int {
	for i in 0 ..< g.star_count {
		if any_colony(g, i) == nil && !g.stars[i].wormhole && i != g.clubhouse {
			found_colony(g, i, 20, PLAYER)
			return i
		}
	}
	return NO_STAR
}

@(test)
test_the_flu :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	c := colony_at(g, g.home)
	c.households = 100
	testing.expect(t, happen(g, .Flu, PLAYER))
	testing.expect_value(t, c.flu, FLU_TURNS)
	testing.expect(t, news_has(g, "A Flu is going round"))
	testing.expect_value(t, g.doormat.kind, Doormat_Kind.Notice)
	room := colony_max(g, g.home)
	for _ in 0 ..< FLU_TURNS {
		colony_troubles(g, g.home, c)
	}
	testing.expect_value(t, c.households, 80) // a fifth, over five turns
	testing.expect_value(t, c.flu, 0)
	testing.expect(t, news_has(g, "has gone round and gone"))
	_ = room
}

@(test)
test_a_revolt :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	testing.expect(t, happen(g, .Revolt, PLAYER))
	bj := g.empires[PLAYER].bj
	for _ in 0 ..< REVOLT_TURNS {
		run_colony(g, g.home)
	}
	testing.expect_value(t, g.empires[PLAYER].bj, bj) // no tax for five turns
	run_colony(g, g.home)
	testing.expect(t, g.empires[PLAYER].bj > bj)
	testing.expect(t, news_has(g, "Revolt at"))
}

@(test)
test_a_find_and_a_car :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	for _ in 0 ..< 10 {
		bj := g.empires[PLAYER].bj
		special := g.stars[g.home].special
		testing.expect(t, happen(g, .Find, PLAYER))
		gained := g.empires[PLAYER].bj - bj
		testing.expect(t, (gained >= FIND_MIN && gained <= FIND_MAX) || (special == .None && g.stars[g.home].special == .Rich))
	}
	known := 0
	for f in Field {
		known += known_count(&g.empires[PLAYER].tech, f)
	}
	testing.expect(t, happen(g, .Car, PLAYER))
	after := 0
	for f in Field {
		after += known_count(&g.empires[PLAYER].tech, f)
	}
	testing.expect_value(t, after, known + 1)
	testing.expect(t, news_has(g, "glovebox"))
}

@(test)
test_a_star_goes_out :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	testing.expect(t, !happen(g, .Star_Out, PLAYER)) // never a home
	star := second_colony(g)
	testing.expect(t, happen(g, .Star_Out, PLAYER))
	testing.expect(t, any_colony(g, star) == nil)
	testing.expect_value(t, g.stars[star].planet, Planet_Type.Dead)
	testing.expect(t, news_has(g, "has gone out"))
}

@(test)
test_the_goat :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	star := second_colony(g)
	testing.expect(t, happen(g, .Goat, PLAYER))
	testing.expect(t, g.goat.alive)
	testing.expect_value(t, g.goat.star, star) // not yer home while there is another
	testing.expect(t, !happen(g, .Goat, PLAYER)) // one Goat at a time
	c := any_colony(g, star)
	before := c.households
	goat_turn(g)
	testing.expect_value(t, c.households, before - GOAT_EATS)
	testing.expect(t, news_has(g, "The Goat ate 2 households"))
	testing.expect(t, g.goat.star != star) // it wanders on
	// Armed ships where it is see it off.
	f := new_fleet(g)
	f.ships[.Pickup] = 5
	dock(g, f, g.goat.star)
	for _ in 0 ..< 10 {
		if !g.goat.alive {
			break
		}
		f.star = g.goat.star
		goat_turn(g)
	}
	testing.expect(t, !g.goat.alive)
	testing.expect_value(t, g.goats_seen_off, 1)
}

@(test)
test_events_come_now_and_then :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	g.turn = 1
	for _ in 0 ..< 100 {
		events_turn(g)
	}
	n := 0
	for v in g.events {
		n += v
	}
	testing.expect_value(t, n, 0) // not before turn 10
	g.turn = EVENTS_FROM
	for _ in 0 ..< 600 {
		events_turn(g)
		g.goat.alive = false
	}
	n = 0
	for v in g.events {
		n += v
	}
	testing.expect(t, n > 20 && n < 70) // about 40
	// The doormat notice: Noted, and back to the map.
	g.doormat = {}
	post_notice(g, "Test notice.")
	g.mode = .Map
	show_doormat(g)
	testing.expect_value(t, g.mode, Mode.Doormat)
	command(g, .South)
	testing.expect_value(t, g.doormat.choice, 0)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Map)
}
