#+build !js
package game

import "core:testing"

// A meeting due, everyone met, a mess at yer home and at a rival's, and someone President.
ruling_game :: proc(g: ^Game, president: int) {
	init_game(g, SEED)
	all_met(g)
	g.council.started = true
	g.council.meetings = 1 // the next is even: no vote for President
	g.council.president = president
	colony_at(g, g.home).waste = MESS_WASTE
	colony_of(g, g.empires[1].home, 1).waste = MESS_WASTE
	for e in 0 ..< g.empire_count {
		g.empires[e].bj = 1000
	}
}

@(test)
test_no_president_no_rulings :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	ruling_game(g, NO_OWNER)
	hold_meeting(g)
	testing.expect(t, !g.council.ruling)
	testing.expect_value(t, g.council.docket_n, 2)
	testing.expect(t, minutes_contain(g, "are a mess. Fined 50 BJ."))
	testing.expect_value(t, g.empires[PLAYER].bj, 950)
	testing.expect(t, g.council.bylaw_voting) // straight on to the bylaw
}

@(test)
test_yer_rulings :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	ruling_game(g, PLAYER)
	hold_meeting(g)
	testing.expect(t, g.council.ruling)
	testing.expect(t, !g.council.bylaw_voting)
	testing.expect_value(t, g.mode, Mode.Council)
	// The first is against you: dismiss it, and whoever brought it minds.
	k := g.council.docket[0]
	testing.expect_value(t, k.accused, PLAYER)
	testing.expect(t, k.complainer == 1 || k.complainer == 2)
	before := g.empires[k.complainer].grudge[PLAYER]
	command(g, .South)
	command(g, .Confirm)
	testing.expect(t, minutes_contain(g, "Complaint, you: the yards at Lot"))
	testing.expect(t, minutes_contain(g, "Dismissed."))
	testing.expect_value(t, g.empires[PLAYER].bj, 1000 - PRESIDENT_DUTY)
	testing.expect_value(t, g.empires[k.complainer].grudge[PLAYER], min(100, before + GRUDGE_DISMISSED))
	testing.expect_value(t, g.council.choice, 0)
	testing.expect(t, g.council.ruling)
	// The second, against rival 1: double it, by a tap.
	r1 := g.empires[1].grudge[PLAYER]
	pointer(g, COLONY_X + 4, vote_row_y(int(Ruling.Double)) + 3, .Touch)
	testing.expect(t, minutes_contain(g, "Doubled, fined 100 BJ."))
	testing.expect_value(t, g.empires[1].bj, 900)
	testing.expect(t, g.empires[1].grudge[PLAYER] >= min(100, r1 + GRUDGE_DOUBLED))
	// Done: on to the bylaw.
	testing.expect(t, !g.council.ruling)
	testing.expect(t, g.council.bylaw_voting)
	testing.expect_value(t, g.rulings[.Dismiss], 1)
	testing.expect_value(t, g.rulings[.Double], 1)
}

@(test)
test_upholding :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	ruling_game(g, PLAYER)
	hold_meeting(g)
	command(g, .Confirm)
	testing.expect(t, minutes_contain(g, "Upheld, fined"))
	testing.expect_value(t, g.empires[PLAYER].bj, 1000 - PRESIDENT_DUTY - (1000 - PRESIDENT_DUTY) * FINE_PERCENT / 100)
}

@(test)
test_a_computer_president_rules :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	ruling_game(g, 1)
	g.empires[1].grudge[PLAYER] = 90
	hold_meeting(g)
	testing.expect(t, !g.council.ruling)
	// You: doubled. Itself: dismissed.
	testing.expect(t, minutes_contain(g, "Complaint, you: the yards"))
	testing.expect(t, minutes_contain(g, "Doubled, fined"))
	testing.expect(t, minutes_contain(g, "Dismissed."))
	testing.expect_value(t, g.empires[1].bj, 1000 - PRESIDENT_DUTY)
	k := Complaint{accused = PLAYER}
	g.empires[1].grudge[PLAYER] = 60
	testing.expect_value(t, ai_ruling(g, 1, &k), Ruling.Uphold)
	g.treaty[1][PLAYER] = .Pact
	g.treaty[PLAYER][1] = .Pact
	testing.expect_value(t, ai_ruling(g, 1, &k), Ruling.Dismiss)
}

@(test)
test_the_complainer_hates_the_accused_most :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	ruling_game(g, NO_OWNER)
	g.empires[1].grudge[PLAYER] = 50
	g.empires[2].grudge[PLAYER] = 80
	complain(g, PLAYER, "test.")
	testing.expect_value(t, g.council.docket[0].complainer, 2)
	for _ in 0 ..< MAX_COMPLAINTS + 3 {
		complain(g, 1, "more.")
	}
	testing.expect_value(t, g.council.docket_n, MAX_COMPLAINTS)
}
