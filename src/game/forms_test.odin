#+build !js
package game

import "core:testing"

// A cluster where you have met both rivals, as the Owls.
met_game :: proc(g: ^Game) {
	init_game(g, SEED)
	choose_race(g, .Owls)
	for e in 1 ..< g.empire_count {
		g.empires[PLAYER].met[e] = true
		g.empires[e].met[PLAYER] = true
	}
}

// The turn moves on and the post is answered (without the rest of the turn).
post_turn :: proc(g: ^Game) {
	g.turn += 1
	forms_turn(g)
}

@(test)
test_pact_forms :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	choose_race(g, .Owls)
	testing.expect(t, file_form(g, PLAYER, 1, .Pact, 0) != "") // not met
	met_game(g)
	// Hated too much: sent back.
	g.empires[1].grudge[PLAYER] = 90
	testing.expect_value(t, file_form(g, PLAYER, 1, .Pact, 0), "")
	testing.expect(t, file_form(g, PLAYER, 1, .Pact, 0) != "") // one in the post already
	testing.expect(t, news_has(g, "Filed: a non-aggression pact"))
	post_turn(g)
	testing.expect(t, !has_pact(g, PLAYER, 1))
	testing.expect(t, news_has(g, "coffee ring"))
	testing.expect_value(t, g.empires[1].grudge[PLAYER], 90 + GRUDGE_REFUSED_PACT - 0)
	// Hated little enough: signed, both ways.
	g.empires[1].grudge[PLAYER] = 10
	file_form(g, PLAYER, 1, .Pact, 0)
	post_turn(g)
	testing.expect(t, has_pact(g, PLAYER, 1) && has_pact(g, 1, PLAYER))
	testing.expect(t, news_has(g, "signed the non-aggression"))
	testing.expect(t, file_form(g, PLAYER, 1, .Pact, 0) != "") // already
	// War tears it up at once, and they mind.
	testing.expect(t, file_form(g, PLAYER, 2, .War, 0) != "") // nothing to tear up
	before := g.empires[1].grudge[PLAYER]
	testing.expect_value(t, file_form(g, PLAYER, 1, .War, 0), "")
	testing.expect(t, !has_pact(g, PLAYER, 1))
	testing.expect_value(t, g.empires[1].grudge[PLAYER], before + GRUDGE_BROKEN_PACT)
}

// With a pact, nobody fights and nobody lands; the rival does not count yer ships as a threat or a target.
@(test)
test_a_pact_keeps_the_peace :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	h := landing(g, 20)
	set_treaty(g, PLAYER, 1, .Pact)
	rival_fleet(g, h, PLAYER, only(.Pickup, 3))
	testing.expect(t, !will_fight(g, h, PLAYER, 1))
	land_troops(g)
	testing.expect(t, colony_of(g, h, 1) != nil)
	testing.expect(t, !threatened(g, 1))
	g.empires[1].intel[h] = {seen = true, owner = PLAYER, strength = 1}
	prey, _, _ := invasion_target(g, 1)
	testing.expect(t, prey == NO_STAR || g.empires[1].intel[prey].owner != PLAYER)
	// Torn up: the Pickups are a threat again, and the Carpools land.
	declare_war(g, PLAYER, 1)
	testing.expect(t, threatened(g, 1))
	land_troops(g)
	testing.expect(t, colony_at(g, h) != nil)
}

@(test)
test_tribute_forms :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	g.empires[PLAYER].bj = 100
	testing.expect(t, file_form(g, PLAYER, 1, .Tribute, 500) != "") // not enough
	theirs := g.empires[1].bj
	testing.expect_value(t, file_form(g, PLAYER, 1, .Tribute, 40), "")
	testing.expect_value(t, g.empires[PLAYER].bj, 60) // enclosed
	post_turn(g)
	testing.expect_value(t, g.empires[1].bj, theirs + 40)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - 40 / TRIBUTE_PER_GRUDGE)
	testing.expect(t, news_has(g, "cashed yer cheque"))
	// Never more than a little below where it started, however much you pay.
	g.empires[PLAYER].bj = 1000
	file_form(g, PLAYER, 1, .Tribute, 1000)
	post_turn(g)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - TRIBUTE_BELOW_FLOOR)
	// And it drifts back up only by what is added; cooling stops at the start.
	grudge_turn(g)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - TRIBUTE_BELOW_FLOOR)
}

@(test)
test_threat_forms :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	// Weak: filed under Ha, two turns later.
	g.empires[1].bj = 100
	file_form(g, PLAYER, 1, .Threat, 50)
	post_turn(g)
	testing.expect(t, !news_has(g, "under Ha"))
	post_turn(g)
	testing.expect(t, news_has(g, "under Ha"))
	testing.expect_value(t, g.empires[1].bj, 100)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU + GRUDGE_THREAT)
	// Strong: they pay.
	fleet_at(g, g.home).ships[.Monster_Truck] = 10
	mine := g.empires[PLAYER].bj
	file_form(g, PLAYER, 1, .Threat, 50)
	post_turn(g)
	post_turn(g)
	testing.expect_value(t, g.empires[1].bj, 50)
	testing.expect_value(t, g.empires[PLAYER].bj, mine + 50)
	testing.expect(t, news_has(g, "remember this"))
}

// A rival tears up a pact when its grudge gets too big, or when it is twice as strong.
@(test)
test_rivals_break_pacts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	set_treaty(g, PLAYER, 1, .Pact)
	g.empires[1].grudge[PLAYER] = 50 // below where it started (tribute), so strength alone does not break it
	post_turn(g)
	testing.expect(t, has_pact(g, PLAYER, 1))
	g.empires[1].grudge[PLAYER] = PACT_BREAK_GRUDGE
	post_turn(g)
	testing.expect(t, !has_pact(g, PLAYER, 1))
	testing.expect(t, news_has(g, "in triplicate"))
	set_treaty(g, PLAYER, 1, .Pact)
	g.empires[1].grudge[PLAYER] = GRUDGE_AT_YOU
	fleet_of(g, g.empires[1].home, 1).ships[.Monster_Truck] = 10
	post_turn(g)
	testing.expect(t, !has_pact(g, PLAYER, 1))
}

// The rivals' forms land on yer doormat once the turn's battles and meetings are done.
@(test)
test_the_doormat :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	// A stronger rival demands; paying calms it a little.
	fleet_of(g, g.empires[1].home, 1).ships[.Monster_Truck] = 10
	g.empires[PLAYER].bj = 200
	for _ in 0 ..< 200 {
		if g.doormat.waiting {
			break
		}
		rival_files(g, 1)
	}
	testing.expect(t, g.doormat.waiting && g.doormat.kind == .Demand && g.doormat.from == 1)
	testing.expect_value(t, g.doormat.amount, 40)
	// It waits while a meeting is on screen.
	g.mode = .Council
	show_doormat(g)
	testing.expect_value(t, g.mode, Mode.Council)
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Doormat)
	command(g, .Confirm) // Pay up
	testing.expect_value(t, g.mode, Mode.Map)
	testing.expect_value(t, g.empires[PLAYER].bj, 160)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - 20)
	// Refusing a demand costs more grudge.
	g.doormat = {waiting = true, kind = .Demand, from = 1, amount = 40}
	show_doormat(g)
	command(g, .South)
	command(g, .Confirm)
	testing.expect_value(t, g.empires[PLAYER].bj, 160)
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - 20 + GRUDGE_THREAT)
	// A pact offer, signed by a tap.
	g.doormat = {waiting = true, kind = .Pact_Offer, from = 2}
	show_doormat(g)
	pointer(g, COLONY_X + 4, doormat_row_y(0) + 2, .Touch)
	testing.expect(t, has_pact(g, PLAYER, 2))
	testing.expect_value(t, g.mode, Mode.Map)
}

// A weaker rival that would rather be left alone offers a pact.
@(test)
test_a_weaker_rival_offers_a_pact :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	fleet_at(g, g.home).ships[.Monster_Truck] = 10
	g.empires[1].grudge[2] = PACT_BUSY_GRUDGE // busy hating the other one
	for _ in 0 ..< 200 {
		if g.doormat.waiting {
			break
		}
		rival_files(g, 1)
	}
	testing.expect(t, g.doormat.waiting && g.doormat.kind == .Pact_Offer)
}

// The desk by keys and by taps.
@(test)
test_the_forms_desk :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	init_game(g, SEED)
	command(g, .Forms)
	testing.expect_value(t, g.mode, Mode.Forms)
	testing.expect_value(t, g.row, DESK_BACK_ROW) // nobody met
	command(g, .Confirm)
	testing.expect_value(t, g.mode, Mode.Map)
	met_game(g)
	command(g, .Forms)
	testing.expect_value(t, g.desk.rival, 1)
	command(g, .North) // To
	command(g, .East)
	testing.expect_value(t, g.desk.rival, 2)
	command(g, .South) // the pact
	command(g, .Confirm)
	testing.expect(t, pending_form(g, PLAYER, 2, .Pact))
	command(g, .South) // trade
	command(g, .South) // tribute
	command(g, .East)
	testing.expect_value(t, g.desk.tribute, 60)
	// A tap on the tribute row's < takes 10 off; a tap on the row picks it, a second files it.
	pointer(g, COLONY_X + DESK_VALUE_COL * GLYPH_W + 1, desk_row_y(DESK_TRIBUTE_ROW) + 2, .Touch)
	testing.expect_value(t, g.desk.tribute, 50)
	g.empires[PLAYER].bj = 100
	pointer(g, COLONY_X + 2, desk_row_y(DESK_THREAT_ROW) + 2, .Touch)
	testing.expect_value(t, g.row, DESK_THREAT_ROW)
	pointer(g, COLONY_X + 2, desk_row_y(DESK_THREAT_ROW) + 2, .Touch)
	testing.expect(t, pending_form(g, PLAYER, 2, .Threat))
	// "P: forms" in the panel, and P again closes.
	command(g, .Forms)
	testing.expect_value(t, g.mode, Mode.Map)
	pointer(g, FORMS_LINK_X + 2, RESEARCH_LINK_Y + 3, .Touch)
	testing.expect_value(t, g.mode, Mode.Forms)
	command(g, .Cancel)
	testing.expect_value(t, g.mode, Mode.Map)
}

// A pact first, then an alliance: refuelling at each other's colonies and shared sight.
@(test)
test_alliances :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	testing.expect(t, file_form(g, PLAYER, 1, .Alliance, 0) != "") // no pact yet
	set_treaty(g, PLAYER, 1, .Pact)
	g.empires[1].grudge[PLAYER] = 90
	file_form(g, PLAYER, 1, .Alliance, 0)
	post_turn(g)
	testing.expect(t, !allied(g, PLAYER, 1))
	testing.expect(t, news_has(g, "declined the alliance"))
	testing.expect(t, !has_pact(g, PLAYER, 1)) // at 95 they tore the pact up too
	set_treaty(g, PLAYER, 1, .Pact)
	g.empires[1].grudge[PLAYER] = 5
	file_form(g, PLAYER, 1, .Alliance, 0)
	post_turn(g)
	testing.expect(t, allied(g, PLAYER, 1) && has_pact(g, PLAYER, 1))
	// Their colony refuels yer ships, and you see what they see.
	h := g.empires[1].home
	testing.expect(t, refuels_at(g, h, PLAYER))
	update_sight(g)
	testing.expect(t, g.empires[PLAYER].sees[h])
	// War tears it all up.
	file_form(g, PLAYER, 1, .War, 0)
	testing.expect(t, !has_pact(g, PLAYER, 1))
	testing.expect(t, !refuels_at(g, h, PLAYER))
}

@(test)
test_trade_agreements :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	g.empires[1].grudge[PLAYER] = 10
	file_form(g, PLAYER, 1, .Trade, 0)
	post_turn(g)
	testing.expect(t, trading(g, PLAYER, 1) && trading(g, 1, PLAYER))
	testing.expect_value(t, g.trade[PLAYER][1], TRADE_START)
	testing.expect(t, file_form(g, PLAYER, 1, .Trade, 0) != "")
	// Each turn each side takes a share of the other's income, and the share grows to the cap.
	mine, theirs := g.empires[PLAYER].bj, g.empires[1].bj
	want_mine := income_of(g, 1) * TRADE_START / 100
	want_theirs := income_of(g, PLAYER) * TRADE_START / 100
	trade_turn(g)
	testing.expect_value(t, g.empires[PLAYER].bj, mine + want_mine)
	testing.expect_value(t, g.empires[1].bj, theirs + want_theirs)
	for _ in 0 ..< 30 {
		trade_turn(g)
	}
	testing.expect_value(t, g.trade[PLAYER][1], TRADE_MAX)
	// Dogs take half as much again.
	g.empires[PLAYER].race = .Dogs
	mine = g.empires[PLAYER].bj
	want := income_of(g, 1) * TRADE_MAX / 100 * 3 / 2
	trade_turn(g)
	testing.expect_value(t, g.empires[PLAYER].bj, mine + want)
	// War ends it; war with only trade is allowed.
	testing.expect_value(t, file_form(g, PLAYER, 1, .War, 0), "")
	testing.expect(t, !trading(g, PLAYER, 1))
	// Hated too much: refused.
	g.empires[2].grudge[PLAYER] = 90
	file_form(g, PLAYER, 2, .Trade, 0)
	post_turn(g)
	testing.expect(t, !trading(g, PLAYER, 2))
}

// Some tech you know and they do not, and the other way round.
give_techs :: proc(g: ^Game) -> (mine, theirs: int) {
	g.empires[PLAYER].tech.known = {}
	g.empires[1].tech.known = {}
	g.empires[PLAYER].tech.known[.Disputes][0] = true
	g.empires[1].tech.known[.Commuting][0] = true
	return tech_id(.Disputes, 0), tech_id(.Commuting, 0)
}

@(test)
test_research_swaps_and_tech_gifts :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	mine, theirs := give_techs(g)
	list, n := giveable(g, PLAYER, 1)
	testing.expect_value(t, n, 1)
	testing.expect_value(t, list[0], mine)
	testing.expect_value(t, swap_back(g, PLAYER, 1), theirs)
	// Refused when hated.
	g.empires[1].grudge[PLAYER] = 90
	testing.expect_value(t, file_form(g, PLAYER, 1, .Swap, 0, mine), "")
	post_turn(g)
	post_turn(g)
	testing.expect(t, !knows(g, PLAYER, theirs))
	// Accepted: each learns the other's.
	g.empires[1].grudge[PLAYER] = 10
	file_form(g, PLAYER, 1, .Swap, 0, mine)
	post_turn(g)
	post_turn(g)
	testing.expect(t, knows(g, PLAYER, theirs) && knows(g, 1, mine))
	testing.expect(t, file_form(g, PLAYER, 1, .Swap, 0, mine) != "") // they know it now
	// A gift: always taken, and pays some grudge off.
	mine, theirs = give_techs(g)
	g.empires[1].grudge[PLAYER] = GRUDGE_AT_YOU
	testing.expect_value(t, file_form(g, PLAYER, 1, .Gift, 0, mine), "")
	post_turn(g)
	testing.expect(t, knows(g, 1, mine))
	testing.expect_value(t, g.empires[1].grudge[PLAYER], GRUDGE_AT_YOU - TECH_TRIBUTE_GRUDGE)
	testing.expect(t, file_form(g, PLAYER, 1, .Gift, 0, mine) != "")
	// Nothing of theirs to swap for.
	g.empires[1].tech.known = {}
	g.empires[1].tech.known[.Disputes][1] = true
	g.empires[PLAYER].tech.known[.Disputes][1] = true
	testing.expect(t, file_form(g, PLAYER, 1, .Swap, 0, mine) != "")
}

// The gift and swap rows step through the techs the rival lacks.
@(test)
test_desk_tech_rows :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	give_techs(g)
	g.empires[PLAYER].tech.known[.Fences][0] = true
	command(g, .Forms)
	testing.expect_value(t, g.desk.gift, tech_id(.Fences, 0))
	g.row = DESK_GIFT_ROW
	command(g, .East)
	testing.expect_value(t, g.desk.gift, tech_id(.Disputes, 0))
	command(g, .Confirm)
	testing.expect(t, pending_form(g, PLAYER, 1, .Gift))
	_, value, _ := desk_row_text(g, DESK_SWAP_ROW)
	testing.expect_value(t, value, tech_name(g.desk.swap))
}

// A rival with a pact who would trade offers it on the doormat.
@(test)
test_a_rival_offers_trade :: proc(t: ^testing.T) {
	g := new(Game)
	defer free(g)
	met_game(g)
	set_treaty(g, PLAYER, 1, .Pact)
	g.empires[1].grudge[PLAYER] = 20
	for _ in 0 ..< 200 {
		if g.doormat.waiting {
			break
		}
		rival_files(g, 1)
	}
	testing.expect(t, g.doormat.waiting && g.doormat.kind == .Trade_Offer)
	show_doormat(g)
	command(g, .Confirm)
	testing.expect(t, trading(g, PLAYER, 1))
}
