#+build !js
package game

import "core:strings"
import "core:testing"

@(test)
test_aims_dealt :: proc(t: ^testing.T) {
	// Each rival gets a different aim, yers none; and the same seed deals the same.
	for seed in u64(1) ..= 20 {
		g := new(Game)
		init_game(g, seed, {size = .Huge, rivals = 5})
		choose_race(g, .Owls)
		testing.expect_value(t, g.empires[PLAYER].aim, Aim.None)
		seen: [Aim]bool
		for e in 1 ..< g.empire_count {
			a := g.empires[e].aim
			testing.expect(t, a != .None)
			testing.expect(t, !seen[a])
			seen[a] = true
		}
		free(g)
	}
	a, b := temper_game(), temper_game()
	defer free(a)
	defer free(b)
	for e in 1 ..< a.empire_count {
		testing.expect_value(t, a.empires[e].aim, b.empires[e].aim)
	}
}

@(test)
test_aim_lines_fit :: proc(t: ^testing.T) {
	for a in Aim {
		if a != .None {
			testing.expect(t, len("Aim: ") + len(AIMS[a].name) + 2 + len(AIMS[a].says) <= 58)
		}
	}
	// The first-contact line names both, and fits the news.
	g := temper_game()
	defer free(g)
	g.empires[1].temper = .Two_Faced
	g.empires[1].aim = .Committee
	temper_news(g, 1)
	m := &g.news[NEWS_LINES - 1]
	s := string(m.text[:m.n])
	testing.expect(t, strings.contains(s, "Two-faced committee types."))
	testing.expect(t, m.n <= NEWS_COLS)
}

@(test)
test_aim_sliders :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	h := g.empires[1].home
	c := any_colony(g, h)
	base: [Aim][Chore]int
	for a in Aim {
		g.empires[1].aim = a
		ai_sliders(g, h, c, false)
		aim_sliders(g, c, false)
		base[a] = c.slider
		total := 0
		for v in c.slider {
			total += v
		}
		testing.expect_value(t, total, 100)
	}
	testing.expect(t, base[.Builder][.Home_Improvement] > base[.None][.Home_Improvement])
	testing.expect(t, base[.Bully][.Parking] > base[.None][.Parking])
	testing.expect(t, base[.Committee][.Lawn_Care] > base[.None][.Lawn_Care])
	testing.expect(t, base[.Tinkerer][.Book_Club] > base[.None][.Book_Club])
}

@(test)
test_aim_war :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	// A Builder starts no war while it can still settle; the others do.
	g.empires[1].aim = .Builder
	testing.expect(t, !goes_to_war(g, 1, true))
	testing.expect(t, goes_to_war(g, 1, false))
	g.empires[1].aim = .Bully
	testing.expect(t, goes_to_war(g, 1, true))
	testing.expect_value(t, attack_percent(g, 1), BULLY_ATTACK_PERCENT)
	testing.expect_value(t, vans_wanted(g, 1), 1)
	g.empires[1].aim = .Builder
	testing.expect_value(t, vans_wanted(g, 1), BUILDER_VANS)
	// A Bully likes the weakest empire it has met best.
	g.empires[1].aim = .Bully
	g.empires[1].met[PLAYER] = true
	g.empires[1].met[2] = true
	w := weakest_met(g, 1)
	testing.expect(t, w == PLAYER || w == 2)
	in_ := Intel{seen = true, owner = w, strength = 1}
	testing.expect_value(t, target_score(g, 1, in_, w), g.empires[1].grudge[w] + BULLY_WEAK_BONUS)
	g.empires[1].aim = .Tinkerer
	testing.expect_value(t, target_score(g, 1, in_, w), g.empires[1].grudge[w])
}

@(test)
test_aim_busybody :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	g.empires[1].aim = .Busybody
	g.empires[2].aim = .Builder
	g.empires[1].met[PLAYER] = true
	g.empires[1].met[2] = true
	g.empires[1].grudge[PLAYER] = 90
	ai_watch(g, 1)
	testing.expect_value(t, g.empires[1].watch_share, AI_WATCH_SHARE * BUSYBODY_WATCH)
	ai_watch(g, 2)
	testing.expect_value(t, g.empires[2].watch_share, AI_WATCH_SHARE)
	// It complains about whoever it hates most, and brings every complaint it can.
	c := &g.council
	c.docket_n, c.docket_i = 0, 0
	busybody_complaints(g)
	testing.expect_value(t, c.docket_n, 1)
	testing.expect_value(t, c.docket[0].accused, PLAYER)
	testing.expect_value(t, c.docket[0].complainer, 1)
	g.empires[2].grudge[PLAYER] = 100
	complain(g, PLAYER, "the yards are a mess.")
	testing.expect_value(t, c.docket[1].complainer, 1)
}

@(test)
test_aim_committee :: proc(t: ^testing.T) {
	g := temper_game({rivals = 3})
	defer free(g)
	g.empires[1].temper = .Touchy
	g.empires[1].aim = .Builder
	plain := pact_value(g, 1, PLAYER)
	g.empires[1].aim = .Committee
	testing.expect_value(t, pact_value(g, 1, PLAYER), plain + COMMITTEE_PACT)
	// The others back a Committee type standing for President more often.
	backed := [2]int{}
	for a, k in ([2]Aim{.Committee, .Builder}) {
		g.empires[1].aim = a
		g.empires[3].aim = .Tinkerer
		g.council.candidates = {1, PLAYER}
		for _ in 0 ..< 400 {
			if rival_vote(g, 3) == .First {
				backed[k] += 1
			}
		}
	}
	testing.expectf(t, backed[0] > backed[1] * 3 / 2, "backed %v", backed)
}

@(test)
test_aim_tinkerer :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	g.empires[1].aim = .Tinkerer
	testing.expect_value(t, deal_value(g, 1, PLAYER, .Swap), SWAP_VALUE + TINKERER_SWAP + (temper_of(g, 1) == .Neighbourly ? NEIGHBOURLY_DEAL : 0))
	// Give each side a tech the other lacks; a swap offer comes, and signing it trades them.
	g.empires[1].met[PLAYER] = true
	g.empires[PLAYER].tech.known[.Disputes][0] = true
	g.empires[1].tech.known[.Disputes][0] = false
	g.empires[1].tech.known[.Fences][0] = true
	g.empires[PLAYER].tech.known[.Fences][0] = false
	offered := false
	for _ in 0 ..< 200 {
		g.doormat = {}
		rival_files(g, 1)
		if g.doormat.waiting && g.doormat.kind == .Swap_Offer {
			offered = true
			break
		}
	}
	testing.expect(t, offered)
	d := g.doormat
	g.doormat.waiting = false
	g.doormat.open = true
	answer_doormat(g, true)
	testing.expect(t, knows(g, PLAYER, d.tech))
	testing.expect(t, knows(g, 1, d.want))
	// Saves keep the aims.
	buf := make([]u8, SAVE_SIZE)
	defer delete(buf)
	write_save(g, buf)
	h := temper_game()
	defer free(h)
	testing.expect(t, read_save(h, buf))
	testing.expect_value(t, h.empires[1].aim, Aim.Tinkerer)
}
