#+build !js
package game

import "core:testing"

// A game with yer Beavers and the rivals' tempers set by hand.
temper_game :: proc(setup := Setup{}) -> ^Game {
	g := new(Game)
	init_game(g, SEED, setup)
	choose_race(g, .Beavers)
	return g
}

@(test)
test_tempers_dealt :: proc(t: ^testing.T) {
	// Each rival gets a different temper, yers none; with five rivals every temper is out there.
	for seed in u64(1) ..= 20 {
		g := new(Game)
		init_game(g, seed, {size = .Huge, rivals = 5})
		choose_race(g, .Owls)
		testing.expect_value(t, g.empires[PLAYER].temper, Temper.None)
		seen: [Temper]bool
		for e in 1 ..< g.empire_count {
			tp := g.empires[e].temper
			testing.expect(t, tp != .None)
			testing.expect(t, !seen[tp])
			seen[tp] = true
		}
		free(g)
	}
	// The same seed deals the same tempers.
	a, b := temper_game(), temper_game()
	defer free(a)
	defer free(b)
	for e in 1 ..< a.empire_count {
		testing.expect_value(t, a.empires[e].temper, b.empires[e].temper)
	}
}

@(test)
test_temper_grudges :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	// Petty: half as much again, and cooling every other turn.
	g.empires[1].temper = .Petty
	g.empires[2].temper = .Neighbourly
	g.empires[1].grudge[PLAYER] = 60
	g.empires[2].grudge[PLAYER] = 60
	add_grudge(g, 1, PLAYER, 10)
	add_grudge(g, 2, PLAYER, 10)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], 75)
	testing.expect_value(t, g.empires[2].grudge[PLAYER], 70)
	for _ in 0 ..< 4 {
		g.turn += 1
		grudge_turn(g)
	}
	testing.expect_value(t, g.empires[1].grudge[PLAYER], 73) // two points in four turns
	testing.expect_value(t, g.empires[2].grudge[PLAYER], 62) // eight
	// Lowering is not grown: tribute pays a Petty grudge off as usual.
	lower_grudge(g, 1, PLAYER, 10)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], 63)
	// Touchy: a caught watcher's grudge is doubled, and an upheld complaint rankles.
	g.empires[1].temper = .Touchy
	testing.expect_value(t, touchy(g, 1, GRUDGE_SPY_CAUGHT), 2 * GRUDGE_SPY_CAUGHT)
	testing.expect_value(t, touchy(g, 2, GRUDGE_SPY_CAUGHT), GRUDGE_SPY_CAUGHT)
	g.empires[1].grudge[PLAYER] = 60
	c := &g.council
	c.docket[0] = {accused = 1, complainer = PLAYER}
	c.docket_n = 1
	c.docket_i = 0
	rule(g, .Uphold)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], 60 + TOUCHY_COMPLAINT)
}

@(test)
test_temper_pacts :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	g.empires[1].temper = .Touchy
	plain := pact_value(g, 1, PLAYER)
	g.empires[1].temper = .Two_Faced
	testing.expect_value(t, pact_value(g, 1, PLAYER), plain + TWO_FACED_PACT)
	g.empires[1].temper = .Neighbourly
	testing.expect_value(t, pact_value(g, 1, PLAYER), plain + NEIGHBOURLY_DEAL)
	testing.expect_value(t, deal_value(g, 1, PLAYER, .Trade), TRADE_VALUE + NEIGHBOURLY_DEAL)
	// Two-faced tears a pact up at a grudge of 65; the others wait for 80.
	set_treaty(g, 1, PLAYER, .Pact)
	g.empires[1].grudge[PLAYER] = TWO_FACED_BREAK
	testing.expect(t, !breaks_pact(g, 1, PLAYER) || empire_strength(g, 1) >= 2 * max(1, empire_strength(g, PLAYER)))
	g.empires[1].temper = .Two_Faced
	testing.expect(t, breaks_pact(g, 1, PLAYER))
}

@(test)
test_temper_pushy :: proc(t: ^testing.T) {
	// A Pushy rival as strong as you demands tribute; another rival as strong does not.
	g := temper_game()
	defer free(g)
	g.empires[1].met[PLAYER] = true
	g.empires[PLAYER].bj = 300
	for &f in g.fleets {
		f = {}
	}
	for i in 0 ..< g.star_count {
		if c := any_colony(g, i); c != nil {
			c.bases = 1
		}
	}
	testing.expect_value(t, empire_strength(g, 1), empire_strength(g, PLAYER))
	demands := [2]int{}
	for tp, k in ([2]Temper{.Pushy, .Touchy}) {
		g.empires[1].temper = tp
		for _ in 0 ..< 200 {
			g.doormat = {}
			rival_files(g, 1)
			if g.doormat.waiting && g.doormat.kind == .Demand {
				demands[k] += 1
			}
		}
	}
	testing.expect(t, demands[0] > 20)
	testing.expect_value(t, demands[1], 0)
}

@(test)
test_temper_shown :: proc(t: ^testing.T) {
	// First contact tells you the temper; a save keeps it.
	g := temper_game()
	defer free(g)
	g.empires[1].temper = .Petty
	temper_news(g, 1)
	found := false
	for i in 0 ..< NEWS_LINES {
		m := &g.news[i]
		s := string(m.text[:m.n])
		for k := 0; k + 5 <= len(s); k += 1 {
			if s[k:k + 5] == "Petty" {
				found = true
			}
		}
	}
	testing.expect(t, found)
	buf := make([]u8, SAVE_SIZE)
	defer delete(buf)
	write_save(g, buf)
	h := temper_game()
	defer free(h)
	testing.expect(t, read_save(h, buf))
	testing.expect_value(t, h.empires[1].temper, Temper.Petty)
}

@(test)
test_temper_lines_fit :: proc(t: ^testing.T) {
	// "Temper: <name>. <says>" fits one line of the forms desk.
	for tp in Temper {
		if tp != .None {
			testing.expect(t, len("Temper: ") + len(TEMPERS[tp].name) + 2 + len(TEMPERS[tp].says) <= 58)
		}
	}
}
