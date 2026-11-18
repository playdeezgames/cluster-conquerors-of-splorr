#+build !js
package game

import "core:strings"
import "core:testing"

// Whether any news line says this.
news_says :: proc(g: ^Game, s: string) -> bool {
	all: strings.Builder
	defer strings.builder_destroy(&all)
	for i in 0 ..< NEWS_LINES {
		m := &g.news[i]
		strings.write_string(&all, string(m.text[:m.n]))
		strings.write_byte(&all, ' ')
	}
	return strings.contains(strings.to_string(all), s)
}

@(test)
test_first_contact_tells_nothing :: proc(t: ^testing.T) {
	g := temper_game()
	defer free(g)
	for e in 1 ..< g.empire_count {
		g.empires[e].met = {}
		g.empires[PLAYER].met[e] = false
		g.empires[e].temper_known, g.empires[e].aim_known = false, false
	}
	// Put a rival's home in sight and let contact happen.
	h := g.empires[1].home
	g.empires[PLAYER].sees[h] = true
	f := new_fleet(g, PLAYER)
	f.ships = ship_one(.Inspector)
	dock(g, f, h)
	update_sight(g)
	testing.expect(t, g.empires[PLAYER].met[1])
	testing.expect(t, !temper_known(g, 1))
	testing.expect(t, !aim_known(g, 1))
	testing.expect(t, !news_says(g, "the neighbours say"))
}

@(test)
test_temper_giveaways :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	// Petty: its grudge at you passes 90. Another temper at 100 gives nothing away.
	g.empires[1].temper, g.empires[2].temper = .Petty, .Touchy
	g.empires[1].grudge[PLAYER] = 85
	add_grudge(g, 2, PLAYER, 100)
	testing.expect(t, !temper_known(g, 2))
	add_grudge(g, 1, PLAYER, 2)
	testing.expect(t, !temper_known(g, 1)) // 88
	add_grudge(g, 1, PLAYER, 2)
	testing.expect(t, temper_known(g, 1))
	testing.expect(t, news_says(g, "are still going on about it. Petty, the neighbours say."))
	testing.expect_value(t, g.giveaways, 1)
	add_grudge(g, 1, PLAYER, 5)
	testing.expect_value(t, g.giveaways, 1) // only once
	// Two-faced: a pact torn up with you, after the news of it.
	g.empires[1].temper = .Two_Faced
	g.empires[1].temper_known = false
	set_treaty(g, 1, PLAYER, .Pact)
	declare_war(g, 1, PLAYER)
	testing.expect(t, temper_known(g, 1))
	m := &g.news[NEWS_LINES - 1]
	testing.expect(t, strings.contains(string(m.text[:m.n]), "the neighbours say"))
	testing.expect(t, news_says(g, "tore up the pact with you. Two-faced"))
	// ...or between two empires you have met.
	g.empires[2].temper = .Two_Faced
	set_treaty(g, 2, 1, .Pact)
	declare_war(g, 2, 1)
	testing.expect(t, temper_known(g, 2))
	testing.expect(t, news_says(g, "tore up their pact with the"))
	// Neighbourly: a pact it offered, signed on yer doormat.
	g.empires[1].temper, g.empires[1].temper_known = .Neighbourly, false
	g.doormat = {open = true, kind = .Pact_Offer, from = 1}
	answer_doormat(g, true)
	testing.expect(t, temper_known(g, 1))
	testing.expect(t, news_says(g, "signed it with a smile. Neighbourly"))
	// A pact refused gives nothing away.
	g.empires[2].temper, g.empires[2].temper_known = .Neighbourly, false
	g.doormat = {open = true, kind = .Pact_Offer, from = 2}
	answer_doormat(g, false)
	testing.expect(t, !temper_known(g, 2))
	// Never from a rival you have not met.
	g.empires[PLAYER].met[2] = false
	g.empires[2].temper = .Petty
	add_grudge(g, 2, PLAYER, 100)
	testing.expect(t, !temper_known(g, 2))
}

@(test)
test_pushy_and_touchy_giveaways :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	ruling_game(g, PLAYER)
	// Touchy: a fine of yers doubled against it.
	g.empires[1].temper, g.empires[2].temper = .Touchy, .Pushy
	for e in 1 ..< g.empire_count {
		g.empires[e].grudge[PLAYER] = 0
	}
	c := &g.council
	c.docket[0] = {accused = 1, complainer = 2}
	c.docket_n, c.docket_i = 1, 0
	rule(g, .Double)
	testing.expect(t, temper_known(g, 1))
	testing.expect(t, news_says(g, "took that very personally. Touchy"))
	// Pushy: a demand on yer doormat.
	rival_fleet(g, g.empires[2].home, 2, only(.Monster_Truck, 20))
	for _ in 0 ..< 200 {
		g.doormat = {}
		rival_files(g, 2)
		if g.doormat.waiting {
			break
		}
	}
	testing.expect_value(t, g.doormat.kind, Doormat_Kind.Demand)
	testing.expect(t, temper_known(g, 2))
}

@(test)
test_aim_giveaways :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	// Builder: the second new colony you see settled.
	g.empires[1].aim = .Builder
	far := NO_STAR
	for i in 0 ..< g.star_count {
		if !g.empires[PLAYER].sees[i] {
			far = i
		}
	}
	builder_settled(g, 1, far)
	testing.expect_value(t, g.empires[1].settled_seen, 0) // not seen
	near := g.home
	builder_settled(g, 1, near)
	testing.expect(t, !aim_known(g, 1))
	builder_settled(g, 1, near)
	testing.expect(t, aim_known(g, 1))
	testing.expect(t, news_says(g, "are unpacking another van. Builders, the neighbours say."))
	// Bully: a battle with the weakest empire it has met (you, the only one it has met).
	g.empires[2].aim = .Bully
	testing.expect_value(t, weakest_met(g, 2), PLAYER)
	bt := Battle {
		star   = g.home,
		owners = {PLAYER, 2},
	}
	bully_battle(g, &bt)
	testing.expect(t, aim_known(g, 2))
	// Busybody: a gripe of its own at a meeting.
	g.empires[1].aim, g.empires[1].aim_known = .Busybody, false
	g.empires[1].grudge[PLAYER] = 90
	g.council.docket_n, g.council.docket_i = 0, 0
	busybody_complaints(g)
	testing.expect(t, aim_known(g, 1))
	testing.expect(t, news_says(g, "Busybodies, the neighbours say."))
	// Committee type: standing for President.
	g.empires[2].aim, g.empires[2].aim_known = .Committee, false
	colony_of(g, g.empires[2].home, 2).households = 500
	start_vote(g)
	testing.expect(t, aim_known(g, 2))
	testing.expect(t, news_says(g, "Committee types, the neighbours say."))
	// Tinkerer: a swap offer.
	g.empires[1].aim, g.empires[1].aim_known = .Tinkerer, false
	g.empires[PLAYER].tech.known[.Disputes][0] = true
	g.empires[1].tech.known[.Disputes][0] = false
	g.empires[1].tech.known[.Fences][0] = true
	g.empires[PLAYER].tech.known[.Fences][0] = false
	for _ in 0 ..< 400 {
		g.doormat = {}
		rival_files(g, 1)
		if g.doormat.waiting && g.doormat.kind == .Swap_Offer {
			break
		}
	}
	testing.expect(t, aim_known(g, 1))
	// Saves keep what you know.
	buf := make([]u8, SAVE_SIZE)
	defer delete(buf)
	write_save(g, buf)
	h := new(Game)
	defer free(h)
	init_game(h, SEED)
	testing.expect(t, read_save(h, buf))
	testing.expect(t, aim_known(h, 1))
	testing.expect(t, aim_known(h, 2))
}

@(test)
test_giveaway_lines_fit :: proc(t: ^testing.T) {
	// The longest species name, every hint: each line fits a message.
	longest := ""
	for r in Race {
		if len(RACES[r].name) > len(longest) {
			longest = RACES[r].name
		}
	}
	for tp in Temper {
		if tp == .None {
			continue
		}
		hint := tp == .Two_Faced ? len(" tore up their pact with the ") + len(longest) : len(TEMPER_HINTS[tp])
		testing.expect(t, len("The ") + len(longest) + hint + 2 + len(TEMPERS[tp].name) + len(", the neighbours say.") <= LOG_CAP)
	}
	for a in Aim {
		if a != .None {
			testing.expect(t, len("The ") + len(longest) + len(AIM_HINTS[a]) + 2 + len(AIMS[a].plural) + len(", the neighbours say.") <= LOG_CAP)
		}
	}
}
